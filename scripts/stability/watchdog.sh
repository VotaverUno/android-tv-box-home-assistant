#!/data/data/com.termux/files/usr/bin/bash
# Watchdog for Home Assistant on Termux.
# - probes http://127.0.0.1:8123/ every INTERVAL seconds
# - restarts HA after FAIL_THRESHOLD consecutive failures, with COOLDOWN (avoid restart storms)
# - restarts HA when MemAvailable is below MEM_MIN_MB
# - prunes old backups when /data free is below DISK_MIN_MB, then alerts
# - sends HA persistent notification + mobile_app push when possible
set -u
H=/data/data/com.termux/files/home
P=/data/data/com.termux/files/usr
export PATH="$P/bin:$PATH"
export HOME="$H"
export SVDIR="$P/var/service"
export TMPDIR="$P/tmp"
mkdir -p "$TMPDIR" "$H/stability/logs" "$H/stability/watchdog"

LOG="$H/stability/logs/watchdog.log"
STATE="${WD_STATE:-$H/stability/watchdog/state}"
PROBE_URL="${WD_PROBE_URL:-http://127.0.0.1:8123/}"
INTERVAL=60
FAIL_THRESHOLD=3
COOLDOWN=1800
GRACE=300
MEM_MIN_MB=120
DISK_MIN_MB=2048

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
st_get() { grep -m1 "^$1=" "$STATE" 2>/dev/null | cut -d= -f2-; }
st_set() {
  local k="$1" v="$2" tmp="$STATE.tmp"
  { grep -v "^$k=" "$STATE" 2>/dev/null; printf '%s=%s\n' "$k" "$v"; } > "$tmp"
  mv -f "$tmp" "$STATE"
}
init_state() {
  [ -f "$STATE" ] || : > "$STATE"
  for kv in fails=0 last_restart=0 last_reason=- was_down=0; do
    k="${kv%%=*}"
    [ -n "$(st_get "$k")" ] || st_set "$k" "${kv#*=}"
  done
}
now() { date +%s; }
probe() {
  [ "${WD_FORCE_PROBE:-}" = "down" ] && return 1
  curl -fsS --max-time 5 -o /dev/null "$PROBE_URL" >/dev/null 2>&1
}
ha_running() { sv status hass 2>/dev/null | grep -q '^run:'; }
ha_uptime() { sv status hass 2>/dev/null | sed -n 's/.*) \([0-9][0-9]*\)s.*/\1/p' | head -1; }
mem_avail() { awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo 2>/dev/null; }
disk_free() { df -Pk /data 2>/dev/null | awk 'NR==2{print int($4/1024)}'; }

notify() {
  local title="$1" msg="$2"
  # ha_notify.py: WeChat push (works when HA is down) + HA notifications (best effort)
  if "$H/ha-venv/bin/python" "$H/stability/scripts/ha_notify.py" "$title" "$msg" >> "$LOG" 2>&1; then
    log "notify ok: $title"
  else
    log "notify best-effort failed: $title"
  fi
}

restart_ha() {
  local reason="$1" last t
  last=$(st_get last_restart); [ -n "$last" ] || last=0
  t=$(now)
  if [ $((t - last)) -lt "$COOLDOWN" ]; then
    log "cooldown: skip restart ($reason), wait $(( (COOLDOWN - (t - last)) / 60 ))min"
    return 0
  fi
  if [ "${WD_DRY_RUN:-0}" = "1" ]; then log "DRY-RUN: would restart ($reason)"; return 0; fi
  log "RESTART reason=$reason"
  notify "看门狗：正在重启 HA" "原因：$reason"
  sv restart hass >> "$LOG" 2>&1 || log "sv restart failed"
  st_set last_restart "$t"
  st_set last_reason "$reason"
}

check_health() {
  local f up
  if probe; then
    if [ "$(st_get was_down)" = "1" ]; then
      log "recovered: web is up again"
      notify "看门狗：HA 已恢复" "服务已恢复正常。"
    fi
    st_set was_down 0
    st_set fails 0
    return 0
  fi
  f=$(st_get fails); [ -n "$f" ] || f=0
  f=$((f + 1)); st_set fails "$f"; st_set was_down 1
  log "probe failed ($f/$FAIL_THRESHOLD)"
  if [ "$f" -lt "$FAIL_THRESHOLD" ]; then return 0; fi
  up=$(ha_uptime); up=${up:-0}
  if ! ha_running; then
    if [ "$up" -lt "$GRACE" ] && [ "$up" -gt 0 ]; then
      log "grace: process young (${up}s), skip"
      return 0
    fi
    log "process not running, trying sv up"
    sv up hass >> "$LOG" 2>&1 || true
    return 0
  fi
  if [ "$up" -lt "$GRACE" ]; then
    log "grace: uptime ${up}s < ${GRACE}s, skip restart"
    return 0
  fi
  restart_ha "health probe failed ${f}x"
}

check_mem() {
  local m
  m=$(mem_avail) || return 0
  [ -n "$m" ] || return 0
  log "mem_available=${m}MB"
  if [ "$m" -lt "$MEM_MIN_MB" ]; then
    restart_ha "memory low: ${m}MB < ${MEM_MIN_MB}MB"
  fi
}

check_disk() {
  local d f
  d=$(disk_free) || return 0
  [ -n "$d" ] || return 0
  log "disk_free=${d}MB"
  if [ "$d" -ge "$DISK_MIN_MB" ]; then return 0; fi
  log "disk low: ${d}MB < ${DISK_MIN_MB}MB, pruning old backups"
  ls -1t "$H"/stability/backups/homeassistant_*.tar.gz 2>/dev/null | tail -n +3 | while read -r f; do
    rm -f "$f" && log "pruned backup: $(basename "$f")"
  done
  d=$(disk_free)
  if [ -n "$d" ] && [ "$d" -lt "$DISK_MIN_MB" ]; then
    notify "看门狗：磁盘空间不足" "剩余 ${d}MB，已清理旧备份仍不足，请人工处理。"
  fi
}

cycle() { check_health; check_mem; check_disk; }

selftest() {
  local pass=0 fail=0
  _ok() { pass=$((pass + 1)); echo "PASS: $*"; }
  _bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
  init_state
  st_set __t 42
  [ "$(st_get __t)" = "42" ] && _ok "state read/write" || _bad "state read/write"
  st_set __t 43
  [ "$(st_get __t)" = "43" ] && _ok "state overwrite" || _bad "state overwrite"
  local m; m=$(mem_avail)
  if [ -n "$m" ] && [ "$m" -gt 0 ]; then _ok "mem_avail parse (${m}MB)"; else _bad "mem_avail parse"; fi
  local d; d=$(disk_free)
  if [ -n "$d" ] && [ "$d" -gt 0 ]; then _ok "disk_free parse (${d}MB)"; else _bad "disk_free parse"; fi
  if probe; then _ok "probe returns up"; else _bad "probe returns down"; fi
  log "selftest run"
  [ -s "$LOG" ] && _ok "log writable" || _bad "log writable"
  echo "-------------------------------------------------"
  echo "WATCHDOG SELFTEST: pass=$pass fail=$fail"
  [ "$fail" -eq 0 ] || exit 1
}

case "${1:-}" in
  --once) init_state; cycle; echo "once done"; echo "--- state"; cat "$STATE"; echo "--- log"; tail -n 5 "$LOG" ;;
  --status) echo "sv: $(sv status hass 2>/dev/null)"; echo "--- state"; cat "$STATE" 2>/dev/null; echo "--- log"; tail -n 10 "$LOG" 2>/dev/null ;;
  --selftest) selftest ;;
  --notify-test) notify "看门狗：测试通知" "这是一条来自盒子看门狗的测试推送 ($(date '+%F %T'))"; echo "notify-test sent (check HA notifications)"; tail -n 2 "$LOG" ;;
  *)
    init_state
    log "watchdog started: interval=${INTERVAL}s threshold=${FAIL_THRESHOLD} cooldown=${COOLDOWN}s mem_min=${MEM_MIN_MB}MB disk_min=${DISK_MIN_MB}MB"
    while :; do cycle; sleep "$INTERVAL"; done
    ;;
esac
