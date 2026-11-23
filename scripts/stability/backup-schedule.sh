#!/data/data/com.termux/files/usr/bin/bash
# Weekly automatic backup + monthly restore drill, supervised by runit.
#   --once / --force-backup / --force-drill / --status
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../env.sh"
H="$TERMUX_HOME"
P="$TERMUX_PREFIX"
export PATH="$P/bin:$PATH"
export HOME="$H"
export TMPDIR="$P/tmp"
LOG="$LOG_DIR/backup-schedule.log"
STATE="$STABILITY_DIR/backup-schedule"
mkdir -p "$STATE" "$TMPDIR"
WEEK=604800
DRILL=$((30 * 86400))

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
get() { [ -f "$STATE/$1" ] && cat "$STATE/$1" || echo 0; }
put() { date +%s > "$STATE/$1"; }
notify() { "$PYTHON_BIN" "$STABILITY_DIR/scripts/ha_notify.py" "$1" "$2" >> "$LOG" 2>&1 || true; }

do_backup() {
  log "backup: start"
  if bash "$H/stability/scripts/backup-ha.sh" >> "$LOG" 2>&1; then
    put last_backup
    log "backup: ok"
    return 0
  fi
  log "backup: FAILED"
  notify "盒子备份失败" "每周自动备份失败，请检查盒子磁盘与脚本。"
  return 1
}

# Restore drill: extract the newest archive into a temp dir and validate that the
# important pieces are present and parseable. We deliberately do NOT use
# yaml.safe_load on configuration.yaml (it contains HA-specific !include tags);
# .storage/core.config_entries is plain JSON and is a much stronger check.
do_drill() {
  log "drill: start"
  local latest tmp ok=1 comps entries
  latest=$(ls -1t "$H"/stability/backups/homeassistant_*.tar.gz 2>/dev/null | head -1)
  if [ -z "${latest:-}" ]; then
    log "drill: FAILED no backup archive"
    put last_drill
    printf 'FAIL %s %s\n' "$(date '+%F %T')" "no archive" > "$STATE/drill-result"
    return 1
  fi
  tmp="$STATE/drill-$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  if ! tar xzf "$latest" -C "$tmp" 2>>"$LOG"; then
    log "drill: FAILED extract $(basename "$latest")"
    ok=0
  fi
  if [ "$ok" = 1 ] && [ ! -s "$tmp/.homeassistant/configuration.yaml" ]; then
    log "drill: FAILED configuration.yaml missing/empty"
    ok=0
  fi
  if [ "$ok" = 1 ] && ! grep -q '^homeassistant:' "$tmp/.homeassistant/configuration.yaml"; then
    log "drill: FAILED configuration.yaml has no homeassistant: key"
    ok=0
  fi
  if [ "$ok" = 1 ]; then
    entries="$tmp/.homeassistant/.storage/core.config_entries"
    if [ -f "$entries" ]; then
      if ! "$H/ha-venv/bin/python" - "$entries" <<'PY' >>"$LOG" 2>&1
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print("drill json ok, entries:", len(data["data"]["entries"]))
PY
      then log "drill: FAILED core.config_entries invalid JSON"; ok=0; fi
    else
      log "drill: FAILED core.config_entries missing"
      ok=0
    fi
  fi
  if [ "$ok" = 1 ]; then
    comps=$(ls -1 "$tmp/.homeassistant/custom_components" 2>/dev/null | wc -l)
    log "drill: custom_components=$comps"
    if [ "$comps" -lt 1 ]; then log "drill: FAILED no custom_components"; ok=0; fi
  fi
  rm -rf "$tmp"
  put last_drill
  if [ "$ok" = 1 ]; then
    printf 'PASS %s %s\n' "$(date '+%F %T')" "$(basename "$latest")" > "$STATE/drill-result"
    log "drill: PASS ($(basename "$latest"))"
    return 0
  fi
  printf 'FAIL %s %s\n' "$(date '+%F %T')" "$(basename "$latest")" > "$STATE/drill-result"
  notify "恢复演练失败" "最新备份无法恢复，请检查。"
  return 1
}

cycle() {
  local t now
  t=$(date +%s)
  now=$(get last_backup)
  if [ "$now" -eq 0 ] || [ $((t - now)) -ge "$WEEK" ]; then do_backup; fi
  now=$(get last_drill)
  if [ "$now" -eq 0 ] || [ $((t - now)) -ge "$DRILL" ]; then do_drill; fi
}

case "${1:-}" in
  --force-backup) do_backup ;;
  --force-drill) do_drill ;;
  --once) cycle ;;
  --status)
    echo "last_backup_ts=$(get last_backup) last_drill_ts=$(get last_drill)"
    echo "drill_result=$(cat "$STATE/drill-result" 2>/dev/null || echo none)"
    tail -n 8 "$LOG" 2>/dev/null
    ;;
  *)
    log "scheduler started (weekly backup / monthly restore drill)"
    while :; do cycle; sleep 3600; done
    ;;
esac
