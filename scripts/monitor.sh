#!/usr/bin/env bash
# Lightweight Linux health check: CPU, memory, disk, load, uptime.
# Prints a report, logs alerts, optionally posts them to a webhook (Slack/Discord/Teams).
# Exit code: 0 = healthy, 1 = at least one threshold breached.
set -euo pipefail

CPU_THRESHOLD="${CPU_THRESHOLD:-85}"      # percent
MEM_THRESHOLD="${MEM_THRESHOLD:-90}"      # percent
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"    # percent, any mounted filesystem
LOG_FILE="${LOG_FILE:-/var/log/server-monitor.log}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
OUTPUT="${OUTPUT:-text}"                  # text | json
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"

alerts=()

log() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') [${HOSTNAME_SHORT}] $*"
  if ! echo "$msg" >> "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="${TMPDIR:-/tmp}/server-monitor.log"; echo "$msg" >> "$LOG_FILE"
  fi
}

cpu_usage() {
  # Two samples of /proc/stat, 1 second apart.
  read -r _ u1 n1 s1 i1 w1 x1 y1 z1 _ < /proc/stat
  sleep 1
  read -r _ u2 n2 s2 i2 w2 x2 y2 z2 _ < /proc/stat
  local idle=$(( (i2 + w2) - (i1 + w1) ))
  local total=$(( (u2+n2+s2+i2+w2+x2+y2+z2) - (u1+n1+s1+i1+w1+x1+y1+z1) ))
  (( total == 0 )) && { echo 0; return; }
  echo $(( (100 * (total - idle)) / total ))
}

mem_usage() {
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END { if (t>0) printf "%d", (t-a)*100/t; else print 0 }' /proc/meminfo
}

disk_report() {
  # mount usage% for real filesystems
  df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR>1 {gsub("%","",$5); print $6, $5}'
}

uptime_human() {
  local secs; secs=$(cut -d. -f1 /proc/uptime)
  printf '%dd %dh %dm' $((secs/86400)) $((secs%86400/3600)) $((secs%3600/60))
}

notify() {
  [[ -z "$ALERT_WEBHOOK_URL" ]] && return 0
  local text="$1"
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"text\": \"${text//\"/\\\"}\"}" "$ALERT_WEBHOOK_URL" >/dev/null || log "WARN webhook delivery failed"
}

check() {
  local name="$1" value="$2" threshold="$3"
  if (( value >= threshold )); then
    alerts+=("${name} at ${value}% (threshold ${threshold}%)")
  fi
}

CPU=$(cpu_usage)
MEM=$(mem_usage)
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
UPTIME=$(uptime_human)
check "CPU" "$CPU" "$CPU_THRESHOLD"
check "Memory" "$MEM" "$MEM_THRESHOLD"

DISKS_JSON=""
while read -r mount pct; do
  [[ -z "$mount" ]] && continue
  check "Disk ${mount}" "$pct" "$DISK_THRESHOLD"
  DISKS_JSON+="{\"mount\":\"${mount}\",\"used_percent\":${pct}},"
done < <(disk_report)
DISKS_JSON="[${DISKS_JSON%,}]"

if [[ "$OUTPUT" == "json" ]]; then
  printf '{"host":"%s","cpu_percent":%s,"memory_percent":%s,"load_avg":"%s","uptime":"%s","disks":%s,"alerts":%s}\n' \
    "$HOSTNAME_SHORT" "$CPU" "$MEM" "$LOAD" "$UPTIME" "$DISKS_JSON" "${#alerts[@]}"
else
  echo "=== Server health: ${HOSTNAME_SHORT} ($(date '+%F %T')) ==="
  echo "Uptime : ${UPTIME}"
  echo "Load   : ${LOAD}"
  echo "CPU    : ${CPU}%"
  echo "Memory : ${MEM}%"
  disk_report | while read -r m p; do printf 'Disk   : %-20s %s%%\n' "$m" "$p"; done
fi

if (( ${#alerts[@]} > 0 )); then
  for a in "${alerts[@]}"; do
    log "ALERT ${a}"
    [[ "$OUTPUT" == "text" ]] && echo "ALERT: ${a}"
    notify "[${HOSTNAME_SHORT}] ALERT ${a}"
  done
  exit 1
fi
log "OK cpu=${CPU}% mem=${MEM}%"
exit 0
