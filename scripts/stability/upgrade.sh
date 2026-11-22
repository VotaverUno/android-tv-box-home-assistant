#!/data/data/com.termux/files/usr/bin/bash
# Upgrade runbook for Home Assistant on this box.
#   --preflight        snapshot config/patches/versions + backup
#   --upgrade [ver]    pip install homeassistant (latest or pinned), then repatch+verify
#   --repatch          re-apply Android/D9/mobile_app/shims patches
#   --verify           self-test + config check + wait for :8123
#   --rollback [--dry-run]   restore config + old HA version, then verify
#   --all [ver]        preflight -> upgrade -> repatch -> verify (auto rollback on failure if --yes)
set -u
H=/data/data/com.termux/files/home
P=/data/data/com.termux/files/usr
export PATH="$P/bin:$PATH"
export HOME="$H"
export TMPDIR="$P/tmp"
VENV="$H/ha-venv"
PY="$VENV/bin/python"
PIP="$VENV/bin/pip"
CFG="$H/.homeassistant"
UP="$H/stability/upgrades"
LOG="$H/stability/logs/upgrade.log"
mkdir -p "$UP" "$TMPDIR" "$(dirname "$LOG")"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }

current_version() { "$PIP" show homeassistant 2>/dev/null | awk '/^Version:/{print $2}'; }
latest_dir() { ls -1d "$UP"/2* 2>/dev/null | sort | tail -1; }
sitecustomize_path() { ls -1 "$VENV"/lib/python3.*/site-packages/sitecustomize.py 2>/dev/null | head -1; }

preflight() {
  local ts d
  ts=$(date +%Y%m%d%H%M%S); d="$UP/$ts"; mkdir -p "$d"
  echo "$d" > "$UP/last"
  log "preflight: dir=$d"
  [ -f "$CFG/configuration.yaml" ] && cp -f "$CFG/configuration.yaml" "$d/configuration.yaml"
  "$PIP" show homeassistant > "$d/pip-homeassistant.txt" 2>&1 || true
  "$PY" --version > "$d/python.txt" 2>&1 || true
  "$PIP" freeze > "$d/pip-freeze.txt" 2>&1 || true
  local sc; sc=$(sitecustomize_path)
  [ -n "$sc" ] && cp -f "$sc" "$d/sitecustomize.py"
  cp -f "$H/fix_ha_android.py" "$d/" 2>/dev/null || true
  cp -f "$H/patch_d9.py" "$d/" 2>/dev/null || true
  cp -f "$H/patch_mobile_app.sh" "$d/" 2>/dev/null || true
  cp -f "$H/shims32.py" "$d/" 2>/dev/null || true
  cp -f "$CFG/custom_components/midea_ac_lan/midea_devices.py" "$d/midea_devices.py" 2>/dev/null || true
  local man; man=$(ls -1 "$VENV"/lib/python3.*/site-packages/homeassistant/components/mobile_app/manifest.json 2>/dev/null | head -1)
  [ -n "$man" ] && cp -f "$man" "$d/mobile_app_manifest.json"
  if bash "$H/stability/scripts/backup-ha.sh" >> "$LOG" 2>&1; then
    local arch; arch=$(ls -1t "$H"/stability/backups/homeassistant_*.tar.gz | head -1)
    echo "$arch" > "$d/backup.txt"
    log "preflight: backup=$arch version=$(current_version)"
  else
    die "preflight: backup failed"
  fi
  echo "$d"
}

repatch() {
  log "repatch: android platform"
  "$PY" "$H/fix_ha_android.py" >> "$LOG" 2>&1 || die "repatch: platform patch failed"
  local d sc; d=$(latest_dir)
  sc=$(sitecustomize_path)
  if [ -n "$sc" ] && [ -f "$d/sitecustomize.py" ]; then
    cp -f "$d/sitecustomize.py" "$sc" && log "repatch: sitecustomize restored"
  fi
  log "repatch: midea D9"
  "$PY" "$H/patch_d9.py" >> "$LOG" 2>&1 || log "repatch: D9 patch failed (continuing)"
  log "repatch: midea D9 program select/buttons"
  "$PY" "$H/stability/scripts/patch-d9-programs.py" >> "$LOG" 2>&1 || log "repatch: D9 program patch failed (continuing)"
  log "repatch: mobile_app manifest"
  bash "$H/patch_mobile_app.sh" >> "$LOG" 2>&1 || log "repatch: mobile_app patch failed (continuing)"
  log "repatch: 32-bit shims"
  if "$PY" - <<'PY' >>"$LOG" 2>&1
import importlib
for name in ("orjson", "ulid_transform", "fnv_hash_fast", "uv"):
    try:
        importlib.import_module(name)
        print("shim ok:", name)
    except Exception as exc:
        print("shim MISSING:", name, exc)
        raise SystemExit(1)
PY
  then log "repatch: shims ok"; else
    log "repatch: shims missing, reinstalling"; "$PY" "$H/shims32.py" >> "$LOG" 2>&1 || die "repatch: shims install failed"
  fi
  log "repatch: done"
}

wait_web() {
  local i
  for i in $(seq 1 60); do
    if curl -fsS --max-time 4 -o /dev/null "http://127.0.0.1:8123/" 2>/dev/null; then return 0; fi
    sleep 3
  done
  return 1
}

verify() {
  log "verify: self-test"
  local st
  st=$(bash "$H/stability/scripts/selftest.sh" 2>&1); echo "$st" >> "$LOG"
  if echo "$st" | grep -q "RESULT: pass=.* fail=0"; then log "verify: selftest PASS"; else log "verify: selftest FAIL"; return 1; fi
  log "verify: config check"
  if timeout 240 "$VENV/bin/hass" --script check_config -c "$CFG" >> "$LOG" 2>&1; then
    log "verify: check_config PASS"
  else
    log "verify: check_config FAIL"; return 1
  fi
  log "verify: waiting for web :8123"
  if wait_web; then log "verify: web UP"; else log "verify: web DOWN"; return 1; fi
  log "verify: PASS"; return 0
}

restart_hass() {
  export SVDIR
  if sv status hass >/dev/null 2>&1; then sv restart hass >> "$LOG" 2>&1; else "$H/start-ha-env.sh" >> "$LOG" 2>&1 & fi
}

do_upgrade() {
  local ver="${1:-}" old
  old=$(current_version)
  log "upgrade: $old -> ${ver:-latest}"
  if [ -n "$ver" ]; then
    "$PIP" install "homeassistant==$ver" >> "$LOG" 2>&1 || die "upgrade: pip install failed"
  else
    "$PIP" install -U homeassistant >> "$LOG" 2>&1 || die "upgrade: pip install -U failed"
  fi
  log "upgrade: installed $(current_version)"
  restart_hass
}

do_rollback() {
  local dry="${1:-}" d old ver arch
  d=$(latest_dir); [ -n "$d" ] || die "rollback: no upgrade snapshot"
  ver=$(awk '/^Version:/{print $2}' "$d/pip-homeassistant.txt" 2>/dev/null)
  arch=$(cat "$d/backup.txt" 2>/dev/null)
  log "rollback: snapshot=$d target_version=${ver:-?} backup=${arch:-?}"
  if [ "$dry" = "--dry-run" ]; then
    log "rollback: DRY-RUN - would restore config, reinstall ${ver:-?}, repatch, verify"
    return 0
  fi
  [ -f "$arch" ] || die "rollback: backup archive missing: $arch"
  log "rollback: restoring config from backup"
  tar xzf "$arch" -C "$H" >> "$LOG" 2>&1 || die "rollback: restore failed"
  if [ -n "${ver:-}" ]; then
    log "rollback: reinstalling homeassistant==$ver"
    "$PIP" install "homeassistant==$ver" >> "$LOG" 2>&1 || die "rollback: pip install failed"
  fi
  repatch
  restart_hass
  verify && log "rollback: PASS" || die "rollback: still failing after rollback"
}

case "${1:-}" in
  --preflight) preflight ;;
  --repatch) repatch ;;
  --verify) verify ;;
  --upgrade) do_upgrade "${2:-}" ;;
  --rollback) do_rollback "${2:-}" ;;
  --all)
    ver="${2:-}"; yes=""
    for a in "$@"; do [ "$a" = "--yes" ] && yes="--yes"; done
    d=$(preflight) || exit 1
    repatch
    do_upgrade "$ver"
    if verify; then log "all: PASS"; else
      log "all: verify failed"
      [ "$yes" = "--yes" ] && do_rollback || log "all: rerun with --yes to auto-rollback"
      exit 1
    fi ;;
  *) echo "usage: $0 --preflight|--repatch|--verify|--upgrade [ver]|--rollback [--dry-run]|--all [ver] [--yes]"; exit 2 ;;
esac
