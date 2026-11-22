#!/data/data/com.termux/files/usr/bin/bash
# Self-test suite for the stability work (C0-C6).
# Exit code 0 = all PASS, 1 = at least one FAIL.
set -u

HOME_DIR=/data/data/com.termux/files/home
PREFIX_DIR=/data/data/com.termux/files/usr
export PATH="$PREFIX_DIR/bin:$PATH"
export SVDIR="$PREFIX_DIR/var/service"
export LOGDIR="$PREFIX_DIR/var/log"
export TMPDIR="$PREFIX_DIR/tmp"
mkdir -p "$TMPDIR" 2>/dev/null
export HOME="$HOME_DIR"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "PASS: $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $*"; }
skip() { SKIP=$((SKIP+1)); echo "SKIP: $*"; }

# T1: newest backup archive is valid and contains configuration.yaml
ARCHIVE=$(ls -1t "$HOME_DIR"/stability/backups/homeassistant_*.tar.gz 2>/dev/null | head -1)
if [ -n "$ARCHIVE" ]; then
  if tar tzf "$ARCHIVE" | grep -qx ".homeassistant/configuration.yaml"; then
    ok "T1 backup archive valid ($(basename "$ARCHIVE"))"
  else
    bad "T1 backup archive missing configuration.yaml"
  fi
else
  bad "T1 no backup archive found"
fi

# T2: HA web UI answers on 8123
if "$PREFIX_DIR/bin/python" - <<'PY' >/dev/null 2>&1
import urllib.request
urllib.request.urlopen("http://127.0.0.1:8123/", timeout=5)
PY
then ok "T2 HA web (8123) answers"; else bad "T2 HA web (8123) does not answer"; fi

# T3: HA finished starting
if grep -q "Home Assistant initialized" "$HOME_DIR/ha.log" 2>/dev/null; then
  ok "T3 HA log contains 'Home Assistant initialized'"
else
  bad "T3 no 'Home Assistant initialized' in ha.log"
fi

# T4: logrotate rule is valid (only if installed)
LR="$PREFIX_DIR/etc/logrotate.d/hass"
if [ -f "$LR" ]; then
  if logrotate -d "$LR" >/dev/null 2>&1; then ok "T4 logrotate rule valid"; else bad "T4 logrotate rule invalid"; fi
else
  skip "T4 no logrotate rule yet"
fi

# T5: package holds (only meaningful after C3)
if apt-mark showhold 2>/dev/null | grep -qx "python" && apt-mark showhold 2>/dev/null | grep -qx "python-pip"; then
  ok "T5 python and python-pip are held"
else
  skip "T5 python/python-pip not held yet (C3 not done)"
fi

# T6: runit service supervised (only after C5)
if command -v sv >/dev/null 2>&1 && sv status hass 2>/dev/null | grep -q "^run:"; then
  ok "T6 runit reports 'run' for hass"
else
  skip "T6 runit not enabled for hass (C5 not done)"
fi

# T7: free space on /data > 2 GB
AVAIL_KB=$(df -k /data 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -gt 2097152 ]; then ok "T7 /data free $((AVAIL_KB/1024))MB"; else bad "T7 /data free low: ${AVAIL_KB:-?}KB"; fi

# T8: snapshots exist for pre-change files
for f in configuration.yaml.before start-ha-env.sh.before; do
  if [ -f "$HOME_DIR/stability/snapshots/$f" ]; then ok "T8 snapshot $f"; else bad "T8 missing snapshot $f"; fi
done

# T9: rollback script present and executable (syntax check)
RB="$HOME_DIR/stability/scripts/rollback.sh"
if [ -f "$RB" ] && bash -n "$RB"; then ok "T9 rollback.sh syntax ok"; else bad "T9 rollback.sh missing/syntax error"; fi

# T10: rollback dry-run does not touch anything
if "$RB" list >/dev/null 2>&1; then ok "T10 rollback.sh list works"; else bad "T10 rollback.sh list failed"; fi

# T12: watchdog runit service is running
if command -v sv >/dev/null 2>&1 && sv status watchdog 2>/dev/null | grep -q "^run:"; then
  ok "T12 watchdog service running"
else
  bad "T12 watchdog service not running"
fi

# T13: watchdog log was written recently (< 10 min)
WLOG="$HOME_DIR/stability/logs/watchdog.log"
if [ -f "$WLOG" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$WLOG" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt 600 ]; then ok "T13 watchdog log fresh (${AGE}s)"; else bad "T13 watchdog log stale (${AGE}s)"; fi
else
  bad "T13 watchdog log missing"
fi

# T14: watchdog state file present
ST="$HOME_DIR/stability/watchdog/state"
if [ -s "$ST" ]; then ok "T14 watchdog state present"; else bad "T14 watchdog state missing"; fi

echo "-------------------------------------------------"
echo "RESULT: pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
