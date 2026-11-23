#!/data/data/com.termux/files/usr/bin/bash
# Weekly/manual backup of the Home Assistant configuration (C1)
# Creates: ~/stability/backups/homeassistant_<stamp>.tar.gz and a copy in
#          /sdcard/Download/ha-backups/ (so adb pull / file manager can reach it)
# Keeps the newest 4 archives in each place.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../env.sh"
HOME_DIR="$TERMUX_HOME"
SRC="$HA_CONFIG"
B1="$BACKUP_DIR"
B2="$BACKUP_COPY_DIR"
KEEP=4
STAMP=$(date +%Y%m%d_%H%M)
NAME="homeassistant_${STAMP}.tar.gz"

mkdir -p "$B1" "$B2"

echo "== backup start $STAMP =="
if tar czf "$B1/$NAME" -C "$HOME_DIR" .homeassistant; then
  echo "created: $B1/$NAME"
else
  echo "ERROR: tar failed"
  exit 1
fi

# integrity check: archive must contain configuration.yaml
if tar tzf "$B1/$NAME" | grep -qx ".homeassistant/configuration.yaml"; then
  echo "check: configuration.yaml present"
else
  echo "ERROR: archive integrity check failed"
  rm -f "$B1/$NAME"
  exit 1
fi

cp -f "$B1/$NAME" "$B2/$NAME"
echo "copied: $B2/$NAME"
sha256sum "$B1/$NAME"

# retention: keep newest N, same count in both places
for dir in "$B1" "$B2"; do
  ls -1t "$dir"/homeassistant_*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -f "$old" && echo "pruned: $old"
  done
done

echo "total in $B1: $(ls -1 "$B1"/homeassistant_*.tar.gz 2>/dev/null | wc -l)"
echo "== backup done =="
