#!/usr/bin/env bash
# switch-ip.sh — switch an ACR Private Endpoint IP allocation between Static and
# Dynamic using the in-place ipconfig re-configuration method (guide 방식 A),
# while recording event-marker timestamps to a CSV for downtime correlation.
#
# This wraps the procedure documented in
# scenarios/acr-private-regional-replication/docs/GUIDE-PE-STATIC-TO-DYNAMIC.md (방식 A).
#
# Events CSV header: timestamp_epoch,iso_time,event
# Emitted events: switch_start, ipconfig_removed, ipconfig_added, switch_end
#
# Usage:
#   switch-ip.sh --pe PE_NAME --rg RG --ipconfig NAME [options]
# Options:
#   --pe NAME           Private endpoint name (required)
#   --rg NAME           Resource group (required)
#   --ipconfig NAME     ip-config name to reconfigure (required)
#   --group-id ID       PE group id (default: registry)
#   --member-name NAME  PE member name (default: registry)
#   --to dynamic|static Target allocation (default: dynamic)
#   --static-ip IP      Required when --to static
#   --events FILE       Event-marker CSV (default: events-<epoch>.csv)
#   --dry-run           Print az commands instead of executing
set -euo pipefail

PE="" ; RG="" ; IPCONFIG="" ; GROUP_ID="registry" ; MEMBER="registry"
TO="dynamic" ; STATIC_IP="" ; EVENTS="" ; DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pe) PE="$2"; shift 2 ;;
    --rg) RG="$2"; shift 2 ;;
    --ipconfig) IPCONFIG="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --member-name) MEMBER="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --static-ip) STATIC_IP="$2"; shift 2 ;;
    --events) EVENTS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for req in PE RG IPCONFIG; do
  if [[ -z "${!req}" ]]; then
    echo "error: --${req,,} is required" >&2; exit 2
  fi
done
if [[ "$TO" == "static" && -z "$STATIC_IP" ]]; then
  echo "error: --static-ip is required when --to static" >&2; exit 2
fi
if [[ "$TO" != "static" && "$TO" != "dynamic" ]]; then
  echo "error: --to must be 'dynamic' or 'static'" >&2; exit 2
fi
if [[ "$DRY_RUN" -eq 0 ]] && ! command -v az >/dev/null 2>&1; then
  echo "error: az CLI is required (or use --dry-run)" >&2; exit 2
fi

EVENTS="${EVENTS:-events-$(date +%s).csv}"
if [[ ! -f "$EVENTS" ]]; then
  echo "timestamp_epoch,iso_time,event" > "$EVENTS"
fi

mark() {
  local event="$1"
  echo "$(date +%s),$(date -u +%Y-%m-%dT%H:%M:%SZ),${event}" >> "$EVENTS"
  echo "[mark] ${event}" >&2
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: $*" >&2
  else
    "$@"
  fi
}

echo "switching PE '$PE' ipconfig '$IPCONFIG' to '$TO' (events -> $EVENTS)" >&2

mark switch_start

run az network private-endpoint ip-config remove \
  --endpoint-name "$PE" -g "$RG" --name "$IPCONFIG"
mark ipconfig_removed

if [[ "$TO" == "dynamic" ]]; then
  # Omitting --private-ip-address yields a Dynamic allocation.
  run az network private-endpoint ip-config add \
    --endpoint-name "$PE" -g "$RG" --name "$IPCONFIG" \
    --group-id "$GROUP_ID" --member-name "$MEMBER"
else
  run az network private-endpoint ip-config add \
    --endpoint-name "$PE" -g "$RG" --name "$IPCONFIG" \
    --group-id "$GROUP_ID" --member-name "$MEMBER" \
    --private-ip-address "$STATIC_IP"
fi
mark ipconfig_added

mark switch_end
echo "switch complete; correlate with: analyze.py PROBE.csv --events $EVENTS" >&2
