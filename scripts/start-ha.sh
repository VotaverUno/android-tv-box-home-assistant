#!/data/data/com.termux/files/usr/bin/bash
# start-ha.sh (venv based) - start HA with a complete Termux build/runtime environment.
# If a still-missing requirement (pymicro-vad) is not installed yet, install it once while
# the compiler is reachable via PATH (that was the "Permission denied:
# arm-linux-androideabi-clang++" cause). Normal starts skip pip entirely.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"
export PREFIX="$TERMUX_PREFIX"
export HOME="$TERMUX_HOME"
export PATH=$PREFIX/bin:$PREFIX/bin/applets:/system/bin
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export TERM=xterm-256color
export PIP_DEFAULT_TIMEOUT=120
export PIP_RETRIES=5
VENV="$VENV_DIR"
LOG="$HA_LOG"
PYMICRO_VAD_VERSION="${PYMICRO_VAD_VERSION:-1.0.1}"
cd "$HOME" || exit 1

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

# importlib.metadata is cheap (no network, no compiler); only call pip when the pinned
# version is really missing.
if "$VENV/bin/python" - "$PYMICRO_VAD_VERSION" <<'PY' >/dev/null 2>&1
import sys
from importlib.metadata import version
sys.exit(0 if version("pymicro-vad") == sys.argv[1] else 1)
PY
then
  echo "== pymicro-vad $PYMICRO_VAD_VERSION present ==" >>"$LOG"
else
  echo "== installing pymicro-vad==$PYMICRO_VAD_VERSION ==" >>"$LOG"
  "$VENV/bin/pip" install --quiet "pymicro-vad==$PYMICRO_VAD_VERSION" >>"$LOG" 2>&1 \
    && echo "pymicro-vad ok" >>"$LOG" || echo "pymicro-vad FAILED (HA will retry on demand)" >>"$LOG"
fi

echo "== starting hass $(date '+%F %T') ==" >>"$LOG"
exec "$VENV/bin/hass" --config "$HOME/.homeassistant" >>"$LOG" 2>&1
