#!/usr/bin/env bash
# Tests for scripts/monitor.sh: healthy run, forced alert, JSON output.
set -euo pipefail
cd "$(dirname "$0")/.."
LOG_FILE="$(mktemp)"
export LOG_FILE

echo "1) healthy run with high thresholds"
CPU_THRESHOLD=101 MEM_THRESHOLD=101 DISK_THRESHOLD=101 ./scripts/monitor.sh >/dev/null
grep -q "OK cpu=" "$LOG_FILE"

echo "2) forced alert (thresholds 0) must exit 1 and log ALERT"
if CPU_THRESHOLD=0 MEM_THRESHOLD=0 DISK_THRESHOLD=0 ./scripts/monitor.sh >/dev/null; then
  echo "expected non-zero exit"; exit 1
fi
grep -q "ALERT Memory" "$LOG_FILE"

echo "3) JSON output parses"
CPU_THRESHOLD=101 MEM_THRESHOLD=101 DISK_THRESHOLD=101 OUTPUT=json ./scripts/monitor.sh \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "cpu_percent" in d and isinstance(d["disks"], list)'

echo "All monitor.sh tests passed"
