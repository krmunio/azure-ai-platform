#!/usr/bin/env bash
# probe.sh — continuously probe an ACR private-endpoint data path and log
# availability to a CSV, so downtime during an IP-type switch can be measured.
#
# The probe issues an unauthenticated HTTPS GET to the registry "/v2/" endpoint.
# A reachable registry returns HTTP 401 (auth required) or 200 — both mean the
# private endpoint path is UP. A connection/DNS/timeout failure means DOWN.
# This needs no registry credentials and isolates network-path availability.
#
# Output CSV header: timestamp_epoch,iso_time,status,detail,latency_ms
#
# Usage:
#   probe.sh --registry myacr.azurecr.io [options]
# Options:
#   --registry FQDN     Registry login server FQDN (required), e.g. myacr.azurecr.io
#   --interval SEC      Seconds between probes (default: 1)
#   --duration SEC      Total run time in seconds (default: run until Ctrl-C)
#   --timeout SEC       Per-probe connect+read timeout (default: 3)
#   --out FILE          Output CSV path (default: probe-<epoch>.csv)
#   --path PATH         Probe path (default: /v2/)
set -euo pipefail

REGISTRY=""
INTERVAL=1
DURATION=0
TIMEOUT=3
OUT=""
PROBE_PATH="/v2/"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --path) PROBE_PATH="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REGISTRY" ]]; then
  echo "error: --registry FQDN is required" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 2
fi

OUT="${OUT:-probe-$(date +%s).csv}"
URL="https://${REGISTRY}${PROBE_PATH}"

echo "timestamp_epoch,iso_time,status,detail,latency_ms" > "$OUT"
echo "probing $URL every ${INTERVAL}s (timeout ${TIMEOUT}s); writing $OUT" >&2

end_epoch=0
if [[ "$DURATION" -gt 0 ]]; then
  end_epoch=$(( $(date +%s) + DURATION ))
fi

while true; do
  ts=$(date +%s)
  iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # -o /dev/null: discard body; -w: emit http_code and total time; -s: silent.
  if out=$(curl -ksS -o /dev/null \
              --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
              -w "%{http_code} %{time_total}" "$URL" 2>/dev/null); then
    code="${out%% *}"
    ttotal="${out##* }"
    latency_ms=$(awk -v t="$ttotal" 'BEGIN{printf "%d", t*1000}')
    if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
      status="up"
    else
      status="down"
    fi
    echo "${ts},${iso},${status},http_${code},${latency_ms}" >> "$OUT"
  else
    # curl non-zero exit = connection/DNS/timeout failure = path is down.
    echo "${ts},${iso},down,curl_error,${TIMEOUT}000" >> "$OUT"
  fi

  if [[ "$end_epoch" -gt 0 && "$(date +%s)" -ge "$end_epoch" ]]; then
    break
  fi
  sleep "$INTERVAL"
done

echo "done; $(($(wc -l < "$OUT") - 1)) samples in $OUT" >&2
