#!/data/data/com.termux/files/usr/bin/bash
# C5: put Home Assistant under runit supervision (termux-services).
set -u
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
export HOME=/data/data/com.termux/files/home
export TMPDIR="$PREFIX/tmp"
export SVDIR="$PREFIX/var/service"
export LOGDIR="$PREFIX/var/log"

SVC="$SVDIR/hass"
mkdir -p "$SVC" "$LOGDIR"

echo "== 1. write service run script =="
cat > "$SVC/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /data/data/com.termux/files/home/start-ha-env.sh
EOF
chmod +x "$SVC/run"
cat "$SVC/run"

echo "== 2. write service log script (svlogd) =="
mkdir -p "$SVC/log"
cat > "$SVC/log/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt /data/data/com.termux/files/usr/var/log/hass
EOF
chmod +x "$SVC/log/run"

echo "== 3. stop current nohup HA instance =="
pkill -f ha-venv/bin/hass 2>/dev/null
sleep 4
pgrep -f ha-venv/bin/hass >/dev/null && echo "WARN: ha still running" || echo "ha stopped"

echo "== 4. start service-daemon (runsvdir) =="
pgrep -f "runsvdir $SVDIR" >/dev/null || (service-daemon start >/dev/null 2>&1 &)
sleep 3
pgrep -f runsvdir >/dev/null && echo "runsvdir running" || echo "WARN: runsvdir not running"

echo "== 5. enable + start hass service =="
rm -f "$SVC/down"
sv up hass 2>&1 || true
sleep 2
sv status hass 2>&1 || true

echo "== 6. wait for HA to come up (max 120s) =="
for i in $(seq 1 24); do
  sleep 5
  if grep -q "Home Assistant initialized" "$HOME/ha.log" 2>/dev/null && \
     "$PREFIX/bin/python" -c 'import urllib.request,sys; urllib.request.urlopen("http://127.0.0.1:8123/",timeout=3)' 2>/dev/null; then
    echo "HA is up after $((i*5))s"
    sv status hass
    exit 0
  fi
done
echo "ERROR: HA did not come up in 120s"
sv status hass || true
tail -n 20 "$HOME/ha.log"
exit 1
