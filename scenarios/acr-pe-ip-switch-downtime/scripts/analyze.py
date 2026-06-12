#!/usr/bin/env python3
"""Analyze ACR private-endpoint availability probe logs to quantify downtime.

Reads a probe CSV produced by ``probe.sh`` and reports availability and the
contiguous outage (downtime) windows. Optionally correlates the outage with
IP-switch event markers produced by ``switch-ip.sh``.

Probe CSV header (see probe.sh):
    timestamp_epoch,iso_time,status,detail,latency_ms
where ``status`` is ``up`` or ``down``.

Events CSV header (optional, see switch-ip.sh):
    timestamp_epoch,iso_time,event

Usage:
    analyze.py PROBE_CSV [--events EVENTS_CSV] [--json]
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass
class Probe:
    epoch: float
    status: str  # "up" or "down"


@dataclass
class Window:
    start_epoch: float
    end_epoch: float
    probe_count: int

    @property
    def duration_s(self) -> float:
        return self.end_epoch - self.start_epoch


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat()


def read_probes(path: str) -> list[Probe]:
    probes: list[Probe] = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        required = {"timestamp_epoch", "status"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError(
                f"probe CSV must have columns {sorted(required)}; got {reader.fieldnames}"
            )
        for row in reader:
            status = row["status"].strip().lower()
            if status not in ("up", "down"):
                raise ValueError(f"invalid status {status!r}; expected up/down")
            probes.append(Probe(epoch=float(row["timestamp_epoch"]), status=status))
    probes.sort(key=lambda p: p.epoch)
    return probes


def read_events(path: str) -> list[tuple[float, str]]:
    events: list[tuple[float, str]] = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            events.append((float(row["timestamp_epoch"]), row["event"].strip()))
    events.sort(key=lambda e: e[0])
    return events


def median_interval(probes: list[Probe]) -> float | None:
    if len(probes) < 2:
        return None
    deltas = sorted(
        probes[i + 1].epoch - probes[i].epoch for i in range(len(probes) - 1)
    )
    mid = len(deltas) // 2
    if len(deltas) % 2:
        return deltas[mid]
    return (deltas[mid - 1] + deltas[mid]) / 2


def find_down_windows(probes: list[Probe]) -> list[Window]:
    """Group contiguous ``down`` probes into outage windows.

    Each window is bounded by the surrounding ``up`` probes when available: the
    window starts at the last ``up`` before the outage and ends at the first
    ``up`` after it. This bounds the true outage by the probe interval rather
    than under-reporting it to the down-sample timestamps only.
    """
    windows: list[Window] = []
    i = 0
    n = len(probes)
    while i < n:
        if probes[i].status != "down":
            i += 1
            continue
        run_start = i
        while i < n and probes[i].status == "down":
            i += 1
        run_end = i - 1  # last down index
        count = run_end - run_start + 1
        # Bound by neighbouring up samples when present.
        start_epoch = (
            probes[run_start - 1].epoch if run_start > 0 else probes[run_start].epoch
        )
        end_epoch = probes[i].epoch if i < n else probes[run_end].epoch
        windows.append(
            Window(start_epoch=start_epoch, end_epoch=end_epoch, probe_count=count)
        )
    return windows


def correlate_events(windows: list[Window], events: list[tuple[float, str]]) -> dict:
    """Compute time from the first switch marker to first/last outage edges."""
    if not events or not windows:
        return {}
    start_marker = next((e for e in events if "start" in e[1].lower()), events[0])
    first_window = windows[0]
    last_window = windows[-1]
    return {
        "switch_marker": start_marker[1],
        "switch_marker_iso": _iso(start_marker[0]),
        "seconds_marker_to_first_outage": round(
            first_window.start_epoch - start_marker[0], 3
        ),
        "seconds_marker_to_recovery": round(last_window.end_epoch - start_marker[0], 3),
    }


def analyze(probe_path: str, events_path: str | None) -> dict:
    probes = read_probes(probe_path)
    if not probes:
        raise ValueError("probe CSV contains no data rows")
    total = len(probes)
    down = sum(1 for p in probes if p.status == "down")
    up = total - down
    windows = find_down_windows(probes)
    total_downtime = round(sum(w.duration_s for w in windows), 3)
    interval = median_interval(probes)

    result: dict = {
        "probe_file": probe_path,
        "total_probes": total,
        "up_probes": up,
        "down_probes": down,
        "availability_pct": round(100.0 * up / total, 4),
        "median_probe_interval_s": round(interval, 3) if interval is not None else None,
        "outage_window_count": len(windows),
        "estimated_total_downtime_s": total_downtime,
        "windows": [
            {
                "start_iso": _iso(w.start_epoch),
                "end_iso": _iso(w.end_epoch),
                "duration_s": round(w.duration_s, 3),
                "down_probe_count": w.probe_count,
            }
            for w in windows
        ],
    }
    if events_path:
        corr = correlate_events(windows, read_events(events_path))
        if corr:
            result["event_correlation"] = corr
    return result


def render_text(r: dict) -> str:
    lines = [
        "=== ACR PE IP-switch downtime report ===",
        f"probe file              : {r['probe_file']}",
        f"total probes            : {r['total_probes']}",
        f"up / down               : {r['up_probes']} / {r['down_probes']}",
        f"availability            : {r['availability_pct']} %",
        f"median probe interval   : {r['median_probe_interval_s']} s",
        f"outage windows          : {r['outage_window_count']}",
        f"estimated downtime total: {r['estimated_total_downtime_s']} s",
    ]
    if r["windows"]:
        lines.append("--- outage windows (bounded by neighbouring up-samples) ---")
        for i, w in enumerate(r["windows"], 1):
            lines.append(
                f"  [{i}] {w['start_iso']} -> {w['end_iso']}  "
                f"({w['duration_s']} s, {w['down_probe_count']} down samples)"
            )
    if "event_correlation" in r:
        c = r["event_correlation"]
        lines.append("--- event correlation ---")
        lines.append(
            f"  switch marker         : {c['switch_marker']} @ {c['switch_marker_iso']}"
        )
        lines.append(f"  marker -> first outage: {c['seconds_marker_to_first_outage']} s")
        lines.append(f"  marker -> recovery    : {c['seconds_marker_to_recovery']} s")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe_csv", help="probe log CSV from probe.sh")
    parser.add_argument(
        "--events", dest="events_csv", help="event marker CSV from switch-ip.sh"
    )
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = parser.parse_args(argv)

    result = analyze(args.probe_csv, args.events_csv)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(render_text(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
