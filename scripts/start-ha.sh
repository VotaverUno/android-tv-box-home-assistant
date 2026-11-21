#!/data/data/com.termux/files/usr/bin/bash
# start-ha.sh (venv based) - start HA with a complete Termux build/runtime environment.
# Also pre-installs any still-missing requirement (pymicro-vad) while the compiler is
# reachable via PATH (that was the "Permission denied: arm-linux-androideabi-clang++" cause).
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:$PREFIX/bin/applets:/system/bin
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export TERM=xterm-256color
export PIP_DEFAULT_TIMEOUT=120
export PIP_RETRIES=5
cd "$HOME" || exit 1

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "== ensure pymicro-vad ==" >>"$HOME/ha.log"
./ha-venv/bin/pip install --quiet "pymicro-vad==1.0.1" >>"$HOME/ha.log" 2>&1 && echo "pymicro-vad ok" >>"$HOME/ha.log" || echo "pymicro-vad FAILED" >>"$HOME/ha.log"

echo "== starting hass ==" >>"$HOME/ha.log"
exec ./ha-venv/bin/hass --config "$HOME/.homeassistant" >>"$HOME/ha.log" 2>&1
