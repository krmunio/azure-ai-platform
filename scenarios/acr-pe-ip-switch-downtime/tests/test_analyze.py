"""Unit tests for analyze.py downtime computation.

Run from the scenario root:
    python3 -m pytest tests/
or without pytest:
    python3 tests/test_analyze.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import analyze  # noqa: E402


def _write_probe(rows):
    """rows: list of (epoch, status). Returns temp file path."""
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, "w") as f:
        f.write("timestamp_epoch,iso_time,status,detail,latency_ms\n")
        for epoch, status in rows:
            f.write(f"{epoch},x,{status},x,0\n")
    return path


def _write_events(rows):
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, "w") as f:
        f.write("timestamp_epoch,iso_time,event\n")
        for epoch, event in rows:
            f.write(f"{epoch},x,{event}\n")
    return path


class TestDowntime(unittest.TestCase):
    def test_single_outage_window_bounded_by_up_samples(self):
        # up at 100, down 101-103, up at 104. Probe interval = 1s.
        rows = [(100, "up"), (101, "down"), (102, "down"), (103, "down"), (104, "up")]
        path = _write_probe(rows)
        try:
            r = analyze.analyze(path, None)
        finally:
            os.unlink(path)
        self.assertEqual(r["total_probes"], 5)
        self.assertEqual(r["down_probes"], 3)
        self.assertEqual(r["outage_window_count"], 1)
        # Bounded window: last up (100) -> first up after (104) = 4s.
        self.assertAlmostEqual(r["estimated_total_downtime_s"], 4.0)
        self.assertAlmostEqual(r["availability_pct"], 40.0)
        self.assertEqual(r["windows"][0]["down_probe_count"], 3)

    def test_no_outage(self):
        rows = [(0, "up"), (1, "up"), (2, "up")]
        path = _write_probe(rows)
        try:
            r = analyze.analyze(path, None)
        finally:
            os.unlink(path)
        self.assertEqual(r["outage_window_count"], 0)
        self.assertEqual(r["estimated_total_downtime_s"], 0)
        self.assertAlmostEqual(r["availability_pct"], 100.0)

    def test_two_separate_outages(self):
        rows = [
            (0, "up"), (1, "down"), (2, "up"),
            (3, "up"), (4, "down"), (5, "down"), (6, "up"),
        ]
        path = _write_probe(rows)
        try:
            r = analyze.analyze(path, None)
        finally:
            os.unlink(path)
        self.assertEqual(r["outage_window_count"], 2)
        # Window 1: 0->2 = 2s; window 2: 3->6 = 3s; total 5s.
        self.assertAlmostEqual(r["estimated_total_downtime_s"], 5.0)

    def test_trailing_outage_no_recovery(self):
        # Outage at the end with no following up-sample.
        rows = [(0, "up"), (1, "down"), (2, "down")]
        path = _write_probe(rows)
        try:
            r = analyze.analyze(path, None)
        finally:
            os.unlink(path)
        self.assertEqual(r["outage_window_count"], 1)
        # last up (0) -> last down (2) = 2s.
        self.assertAlmostEqual(r["estimated_total_downtime_s"], 2.0)

    def test_event_correlation(self):
        rows = [(100, "up"), (101, "down"), (102, "down"), (103, "up")]
        probe = _write_probe(rows)
        events = _write_events([(100, "switch_start"), (103, "switch_end")])
        try:
            r = analyze.analyze(probe, events)
        finally:
            os.unlink(probe)
            os.unlink(events)
        self.assertIn("event_correlation", r)
        c = r["event_correlation"]
        self.assertEqual(c["switch_marker"], "switch_start")
        # window: 100 -> 103; marker at 100.
        self.assertAlmostEqual(c["seconds_marker_to_first_outage"], 0.0)
        self.assertAlmostEqual(c["seconds_marker_to_recovery"], 3.0)

    def test_invalid_status_rejected(self):
        path = _write_probe([(0, "maybe")])
        try:
            with self.assertRaises(ValueError):
                analyze.analyze(path, None)
        finally:
            os.unlink(path)

    def test_empty_probe_rejected(self):
        path = _write_probe([])
        try:
            with self.assertRaises(ValueError):
                analyze.analyze(path, None)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
