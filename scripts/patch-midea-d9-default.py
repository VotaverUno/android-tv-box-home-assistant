"""Patch midea_ac_lan midea_devices.py so D9 (Washer Dryer Combo) entities are default-enabled.

Why: the D9 block in midea_devices.py has no `"default": True` on any entity config.
The platform setup code only creates entities when `config.get("default")` is truthy
(extra entities can be enabled per entry), so a D9 device is polled but ends up with
ZERO entities in HA.

This patch adds `"default": True,` to every entity config inside the `0xD9: { ... }`
block. It is idempotent and backs up the original file first.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

PATH = Path(
    "/data/data/com.termux/files/home/.homeassistant/custom_components/"
    "midea_ac_lan/midea_devices.py"
)
BACKUP = Path(
    "/data/data/com.termux/files/home/stability/snapshots/"
    "midea_devices.py.before_d9_default"
)

BLOCK_START = re.compile(r"^    0xD9: \{$", re.M)
# next device-type key at the same indent, e.g. "    0xDA: {" or "    0xDC: {"
NEXT_BLOCK = re.compile(r"^    0x[0-9A-Fa-f]{2}: \{", re.M)


def main() -> int:
    text = PATH.read_text(encoding="utf-8")
    start_match = BLOCK_START.search(text)
    if start_match is None:
        print("ERROR: 0xD9 block not found")
        return 1
    start = start_match.start()
    next_match = NEXT_BLOCK.search(text, start_match.end())
    end = next_match.start() if next_match else len(text)
    block = text[start:end]

    if '"default": True' in block:
        print("already patched: 0xD9 block already has default flags")
        return 0

    patched_lines = []
    added = 0
    for line in block.splitlines(keepends=True):
        patched_lines.append(line)
        stripped = line.strip()
        if stripped in ('"type": Platform.SWITCH,', '"type": Platform.SENSOR,'):
            indent = line[: len(line) - len(line.lstrip())]
            patched_lines.append(f'{indent}"default": True,\n')
            added += 1

    new_block = "".join(patched_lines)
    if added == 0:
        print("ERROR: no SWITCH/SENSOR type lines found inside 0xD9 block")
        return 2

    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PATH, BACKUP)
    PATH.write_text(text[:start] + new_block + text[end:], encoding="utf-8")
    print(f"patched {added} entity configs in 0xD9 block")
    print(f"backup: {BACKUP}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
