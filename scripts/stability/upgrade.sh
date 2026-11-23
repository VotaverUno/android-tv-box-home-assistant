#!/data/data/com.termux/files/usr/bin/bash
# Upgrade runbook for Home Assistant on this box.
#   --preflight        snapshot config/patches/versions + backup
#   --upgrade [ver]    install homeassistant (latest or pinned) safely, repatch, restart
#   --repatch          re-apply Android/DNS/D9/mobile_app/shims patches
#   --verify           self-test + config check + wait for :8123
#   --rollback [--dry-run]   restore config + old HA version, then verify
#   --all [ver] [--yes]      preflight -> upgrade(+repatch) -> verify (auto rollback if --yes)
#
# Safe install order (avoids on-device Rust builds and an unpatched restart):
#   1. pip install --no-deps homeassistant==NEW   (only HA itself)
#   2. repatch: platform check, sitecustomize, mobile_app, D9, and the 32-bit shims,
#      re-generated with the versions NEW pins (read from its metadata)
#   3. pip install homeassistant==NEW             (remaining deps; shims now satisfy pins)
#   4. restart
#
# Patch scripts are looked up (first hit wins) in $HA_PATCH_DIR (default ~), ~/stability/scripts,
# this script's directory and its parent (a repo checkout). Repo names are preferred, the
# legacy names used on the original box (fix_ha_android.py, patch_d9.py, ...) still work.
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
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
export SVDIR="${SVDIR:-$P/var/service}"
mkdir -p "$UP" "$TMPDIR" "$(dirname "$LOG")"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }
die() { log "ERROR: $*"; exit 1; }

find_script() {
  local n d
  for n in "$@"; do
    for d in "${HA_PATCH_DIR:-$H}" "$H/stability/scripts" "$SELF_DIR" "$SELF_DIR/.."; do
      [ -f "$d/$n" ] && { echo "$d/$n"; return 0; }
    done
  done
  return 1
}
S_PLATFORM() { find_script patch-android-platform.py fix_ha_android.py; }
S_D9()       { find_script patch-midea-d9-default.py patch_d9.py; }
S_D9PROG()   { find_script patch-d9-programs.py; }
S_MOBILE()   { find_script patch-mobile-app-manifest.py patch_mobile_app.sh; }
S_SHIMS()    { find_script shims-32bit.py shims32.py; }
S_SITE()     { find_script sitecustomize.py; }

current_version() { "$PIP" show homeassistant 2>/dev/null | awk '/^Version:/{print $2}'; }
latest_dir() { ls -1d "$UP"/2* 2>/dev/null | sort | tail -1; }
sitecustomize_path() { "$PY" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"]+"/sitecustomize.py")'; }

run_patch() {  # run_patch <label> <script> ; .sh via bash, everything else via venv python
  local label="$1" script="$2"
  log "repatch: $label ($script)"
  case "$script" in
    *.sh) bash "$script" >> "$LOG" 2>&1 ;;
    *)    "$PY" "$script" >> "$LOG" 2>&1 ;;
  esac
}

preflight() {
  local ts d s
  ts=$(date +%Y%m%d%H%M%S); d="$UP/$ts"; mkdir -p "$d"
  echo "$d" > "$UP/last"
  log "preflight: dir=$d"
  [ -f "$CFG/configuration.yaml" ] && cp -f "$CFG/configuration.yaml" "$d/configuration.yaml"
  "$PIP" show homeassistant > "$d/pip-homeassistant.txt" 2>&1 || true
  "$PY" --version > "$d/python.txt" 2>&1 || true
  "$PIP" freeze > "$d/pip-freeze.txt" 2>&1 || true
  local sc; sc=$(sitecustomize_path)
  [ -f "$sc" ] && cp -f "$sc" "$d/sitecustomize.py"
  for s in "$(S_PLATFORM)" "$(S_D9)" "$(S_D9PROG)" "$(S_MOBILE)" "$(S_SHIMS)"; do
    [ -n "$s" ] && cp -f "$s" "$d/" 2>/dev/null
  done
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

shims_needed() {
  # shims are only for 32-bit boxes: run when they are already in use or a module is missing
  ls "$VENV"/lib/python3.*/site-packages/*.dist-info/INSTALLER 2>/dev/null \
    | xargs grep -l '^shims32' >/dev/null 2>&1 && return 0
  "$PY" -c 'import orjson, ulid_transform, fnv_hash_fast' >/dev/null 2>&1 || return 0
  return 1
}

repatch() {
  local s d sc
  s=$(S_PLATFORM) || die "repatch: patch-android-platform.py not found"
  run_patch "android platform" "$s" || die "repatch: platform patch failed"

  sc=$(sitecustomize_path); d=$(latest_dir)
  if [ -n "$d" ] && [ -f "$d/sitecustomize.py" ]; then s="$d/sitecustomize.py"; else s=$(S_SITE || true); fi
  if [ -n "$s" ]; then
    if cmp -s "$s" "$sc"; then log "repatch: sitecustomize ok"; else cp -f "$s" "$sc" && log "repatch: sitecustomize installed from $s"; fi
  else
    log "repatch: WARNING sitecustomize.py not found - cloud logins will fail"
  fi

  if s=$(S_MOBILE); then run_patch "mobile_app manifest" "$s" || log "repatch: mobile_app patch failed (continuing)"; fi
  if s=$(S_D9); then run_patch "midea D9" "$s" || log "repatch: D9 patch failed (continuing)"; fi
  if s=$(S_D9PROG); then run_patch "midea D9 programs" "$s" || log "repatch: D9 program patch failed (continuing)"; fi

  if shims_needed; then
    s=$(S_SHIMS) || die "repatch: shims-32bit.py not found"
    run_patch "32-bit shims (versions from installed homeassistant)" "$s" || die "repatch: shims install failed"
    "$PY" -c 'import orjson, ulid_transform, fnv_hash_fast, uv' >> "$LOG" 2>&1 || die "repatch: shims not importable"
  else
    log "repatch: native orjson/ulid/fnv present, shims not needed"
  fi
  log "repatch: done"
}

install_ha() {  # install_ha <version|""> ; HA first without deps, repatch, then deps
  local ver="${1:-}" spec
  if [ -n "$ver" ]; then
    "$PIP" install --no-deps "homeassistant==$ver" >> "$LOG" 2>&1 || die "install: pip install --no-deps homeassistant==$ver failed"
  else
    "$PIP" install --no-deps -U homeassistant >> "$LOG" 2>&1 || die "install: pip install --no-deps -U homeassistant failed"
  fi
  spec="homeassistant==$(current_version)"
  log "install: $spec installed (no deps), repatching before resolving dependencies"
  repatch
  "$PIP" install "$spec" >> "$LOG" 2>&1 || die "install: dependency install for $spec failed (see $LOG)"
  log "install: dependencies ok for $spec"
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
  local s
  if sv status hass >/dev/null 2>&1; then
    log "restart: sv restart hass"
    sv restart hass >> "$LOG" 2>&1
  elif s=$(find_script start-ha.sh start-ha-env.sh); then
    log "restart: no runit service, starting $s in background"
    pkill -f "$VENV/bin/hass" 2>/dev/null; sleep 3
    nohup bash "$s" >/dev/null 2>&1 &
  else
    die "restart: neither runit service 'hass' nor start-ha.sh found"
  fi
}

do_upgrade() {
  local ver="${1:-}" old
  old=$(current_version)
  log "upgrade: $old -> ${ver:-latest}"
  install_ha "$ver"
  log "upgrade: installed $(current_version)"
  restart_hass
}

do_rollback() {
  local dry="${1:-}" d ver arch
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
    install_ha "$ver"
  else
    repatch
  fi
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
    shift; ver=""; yes=""
    for a in "$@"; do
      case "$a" in
        --yes) yes="--yes" ;;
        -*) die "all: unknown option $a" ;;
        *) ver="$a" ;;
      esac
    done
    preflight >/dev/null || exit 1
    do_upgrade "$ver"
    if verify; then log "all: PASS"; else
      log "all: verify failed"
      if [ "$yes" = "--yes" ]; then do_rollback; else log "all: rerun with --yes to auto-rollback"; fi
      exit 1
    fi ;;
  *) echo "usage: $0 --preflight|--repatch|--verify|--upgrade [ver]|--rollback [--dry-run]|--all [ver] [--yes]"; exit 2 ;;
esac
