#!/data/data/com.termux/files/usr/bin/bash
# Rollback helper for the stability work (C0-C6).
#
#   rollback.sh list                 show available backups / current state
#   rollback.sh config [archive]     restore ~/.homeassistant (stops/starts HA)
#   rollback.sh runit                disable runit for hass, restore nohup boot
#   rollback.sh hold                 unhold python / python-pip
#   rollback.sh logrotate            remove the HA logrotate rule
#   rollback.sh all                  config + runit + hold + logrotate
#
# Every destructive action prints what it will do first; pass --yes to execute.
set -u

HOME_DIR=/data/data/com.termux/files/home
PREFIX_DIR=/data/data/com.termux/files/usr
export PATH="$PREFIX_DIR/bin:$PATH"
export HOME="$HOME_DIR"
SNAP="$HOME_DIR/stability/snapshots"
B1="$HOME_DIR/stability/backups"
LR="$PREFIX_DIR/etc/logrotate.d/hass"
BOOT="$HOME_DIR/.termux/boot/start-ha.sh"
YES=0
for arg in "$@"; do [ "$arg" = "--yes" ] && YES=1; done

log() { echo "[rollback] $*"; }

stop_ha() {
  pkill -f ha-venv/bin/hass 2>/dev/null
  sleep 3
}
start_ha_nohup() {
  cd "$HOME_DIR" || exit 1
  nohup sh start-ha-env.sh >/dev/null 2>&1 &
  sleep 1
  log "HA started via nohup (wait ~40s, check: grep initialized ~/ha.log)"
}

case "${1:-list}" in
  list)
    log "backups in $B1:"
    ls -1t "$B1"/homeassistant_*.tar.gz 2>/dev/null || log "  (none)"
    log "snapshots in $SNAP:"
    ls -1 "$SNAP" 2>/dev/null || log "  (none)"
    log "runit service:"; sv status hass 2>/dev/null || log "  (not installed/enabled)"
    log "apt holds:"; apt-mark showhold 2>/dev/null || true
    log "logrotate rule:"; ls -l "$LR" 2>/dev/null || log "  (none)"
    ;;
  config)
    ARCHIVE="${2:-}"
    [ "$ARCHIVE" = "--yes" ] && ARCHIVE=""
    if [ -z "$ARCHIVE" ]; then
      ARCHIVE=$(ls -1t "$B1"/homeassistant_*.tar.gz 2>/dev/null | head -1)
    fi
    [ -z "$ARCHIVE" ] && { log "no archive found"; exit 1; }
    log "restore config from: $ARCHIVE"
    log "  -> stop HA, move current .homeassistant to .homeassistant.broken_$(date +%H%M), extract archive"
    [ "$YES" = 1 ] || { log "dry-run only. re-run with --yes"; exit 0; }
    stop_ha
    mv "$HOME_DIR/.homeassistant" "$HOME_DIR/.homeassistant.broken_$(date +%H%M)" 2>/dev/null
    tar xzf "$ARCHIVE" -C "$HOME_DIR" || { log "ERROR extract failed"; exit 1; }
    start_ha_nohup
    ;;
  runit)
    log "disable runit, restore boot script, then start HA via nohup"
    [ "$YES" = 1 ] || { log "dry-run only. re-run with --yes"; exit 0; }
    sv-disable hass 2>/dev/null
    sv down hass 2>/dev/null
    if [ -f "$SNAP/boot-start-ha.sh.before" ]; then
      cp -f "$SNAP/boot-start-ha.sh.before" "$BOOT"
      log "boot script restored from snapshot"
    fi
    stop_ha
    start_ha_nohup
    ;;
  hold)
    log "unhold python / python-pip"
    [ "$YES" = 1 ] || { log "dry-run only. re-run with --yes"; exit 0; }
    apt-mark unhold python python-pip 2>/dev/null
    apt-mark showhold
    ;;
  logrotate)
    log "remove $LR"
    [ "$YES" = 1 ] || { log "dry-run only. re-run with --yes"; exit 0; }
    rm -f "$LR"
    log "removed"
    ;;
  all)
    log "full rollback: runit -> hold -> logrotate -> config"
    [ "$YES" = 1 ] || { log "dry-run only. re-run with --yes"; exit 0; }
    "$0" runit --yes
    "$0" hold --yes
    "$0" logrotate --yes
    "$0" config --yes
    ;;
  *)
    echo "usage: rollback.sh {list|config|runit|hold|logrotate|all} [--yes]"
    exit 2
    ;;
esac
