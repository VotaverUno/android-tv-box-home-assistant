#!/data/data/com.termux/files/usr/bin/bash
# env.sh - shared paths/environment for this project's scripts (portable defaults).
#
# Goal: keep Termux working out of the box, but allow another environment to override
# every important path with environment variables, e.g.:
#
#   TERMUX_HOME=/home/ha TERMUX_PREFIX=/usr bash scripts/stability/selftest.sh
#
# Scripts keep their original variable names (H / P / HOME_DIR / PREFIX_DIR) as aliases,
# so only the first few lines of each script need to source this file.

# --- detect prefix/home ---------------------------------------------------
: "${TERMUX_PREFIX:=}"
if [ -z "$TERMUX_PREFIX" ]; then
  if [ -d /data/data/com.termux/files/usr ]; then
    TERMUX_PREFIX=/data/data/com.termux/files/usr
  elif [ -n "${PREFIX:-}" ]; then
    TERMUX_PREFIX="$PREFIX"
  else
    TERMUX_PREFIX=/usr/local
  fi
fi

: "${TERMUX_HOME:=}"
if [ -z "$TERMUX_HOME" ]; then
  if [ -d /data/data/com.termux/files/home ]; then
    TERMUX_HOME=/data/data/com.termux/files/home
  else
    TERMUX_HOME="${HOME:-/root}"
  fi
fi

# --- tunable paths --------------------------------------------------------
: "${HA_CONFIG:=$TERMUX_HOME/.homeassistant}"
: "${VENV_DIR:=$TERMUX_HOME/ha-venv}"
: "${PYTHON_BIN:=$VENV_DIR/bin/python}"
: "${HA_LOG:=$TERMUX_HOME/ha.log}"
: "${HA_URL:=http://127.0.0.1:8123/}"
: "${STABILITY_DIR:=$TERMUX_HOME/stability}"
: "${LOG_DIR:=$STABILITY_DIR/logs}"
: "${SNAPSHOT_DIR:=$STABILITY_DIR/snapshots}"
: "${BACKUP_DIR:=$STABILITY_DIR/backups}"
: "${BACKUP_COPY_DIR:=/sdcard/Download/ha-backups}"
: "${SVC_DIR:=$TERMUX_PREFIX/var/service}"
: "${SVLOGD_DIR:=$TERMUX_PREFIX/var/log}"
: "${LOGROTATE_DIR:=$TERMUX_PREFIX/etc/logrotate.d}"

# --- exported environment -------------------------------------------------
export TERMUX_PREFIX TERMUX_HOME HA_CONFIG VENV_DIR PYTHON_BIN HA_LOG HA_URL
export STABILITY_DIR LOG_DIR SNAPSHOT_DIR BACKUP_DIR BACKUP_COPY_DIR
export SVC_DIR SVLOGD_DIR LOGROTATE_DIR

export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/bin/applets:/system/bin:$PATH"
export HOME="$TERMUX_HOME"
export TMPDIR="${TMPDIR:-$TERMUX_PREFIX/tmp}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$TERMUX_PREFIX/lib}"
export SVDIR="$SVC_DIR"
export LOGDIR="$SVLOGD_DIR"
mkdir -p "$TMPDIR" "$LOG_DIR" 2>/dev/null || true

# aliases used by the existing scripts
H="$TERMUX_HOME"
P="$TERMUX_PREFIX"
HOME_DIR="$TERMUX_HOME"
PREFIX_DIR="$TERMUX_PREFIX"
