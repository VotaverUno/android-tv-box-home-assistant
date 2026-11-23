#!/usr/bin/env python3
"""Patch midea_ac_lan midea_devices.py so D9 (Washer Dryer Combo) entities are default-enabled.

Why: the D9 block in midea_devices.py has no `"default": True` on any entity config.
The platform setup code only creates entities when `config.get("default")` is truthy
(extra entities can be enabled per entry), so a D9 device is polled but ends up with
ZERO entities in HA.

This patch adds `"default": True,` to every entity config (any Platform.* type) inside
the device block that does not already declare "default". Entities that explicitly
say `"default": False` are left alone. It is idempotent and backs up the original
file before writing.

Usage:
    python patch-midea-d9-default.py                    # patch ~/.homeassistant/...
    python patch-midea-d9-default.py --dry-run          # only report
    python patch-midea-d9-default.py --config /path/to/ha-config --device 0xD9
    python patch-midea-d9-default.py --file /path/to/midea_devices.py
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time
from pathlib import Path

DEFAULT_CONFIG = Path(os.environ.get("HA_CONFIG", Path.home() / ".homeassistant"))
DEFAULT_SNAPSHOTS = Path(os.environ.get("HA_SNAPSHOT_DIR", Path.home() / "stability" / "snapshots"))
REL_PATH = Path("custom_components") / "midea_ac_lan" / "midea_devices.py"

# next device-type key at the same indent, e.g. "    0xDA: {" or "    0xDC: {"
NEXT_BLOCK = re.compile(r"^    0x[0-9A-Fa-f]{2}: \{", re.M)
TYPE_LINE = re.compile(r'^(?P<indent>\s+)"type": Platform\.\w+,\s*$')


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def patch_block(block: str) -> tuple[str, int, int]:
    """Return (patched block, entities patched, entities total)."""
    lines = block.splitlines(keepends=True)
    out: list[str] = []
    added = total = 0
    for i, line in enumerate(lines):
        out.append(line)
        match = TYPE_LINE.match(line)
        if not match:
            continue
        total += 1
        level = _indent(line)
        has_default = False
        # scan the rest of this entity dict (ends at a closing brace indented less)
        for nxt in lines[i + 1 :]:
            if nxt.strip() and _indent(nxt) < level:
                break
            if nxt.lstrip().startswith('"default"'):
                has_default = True
                break
        # also look back inside the dict ("default" may precede "type")
        for prev in reversed(lines[:i]):
            if prev.strip() and _indent(prev) < level:
                break
            if prev.lstrip().startswith('"default"'):
                has_default = True
                break
        if not has_default:
            out.append(f'{match.group("indent")}"default": True,\n')
            added += 1
    return "".join(out), added, total


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="HA config dir")
    parser.add_argument("--file", type=Path, help="explicit path to midea_devices.py")
    parser.add_argument("--device", default="0xD9", help="device type key, default 0xD9")
    parser.add_argument("--backup-dir", type=Path, default=DEFAULT_SNAPSHOTS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    path: Path = args.file or args.config / REL_PATH
    if not path.is_file():
        print(f"ERROR: {path} not found (use --config or --file)", file=sys.stderr)
        return 1
    device = args.device.upper().replace("0X", "0x")
    text = path.read_text(encoding="utf-8")
    start_match = re.search(rf"^    {re.escape(device)}: \{{$", text, re.M | re.I)
    if start_match is None:
        print(f"ERROR: {device} block not found in {path}", file=sys.stderr)
        return 1
    start = start_match.start()
    next_match = NEXT_BLOCK.search(text, start_match.end())
    end = next_match.start() if next_match else len(text)

    new_block, added, total = patch_block(text[start:end])
    if total == 0:
        print(f"ERROR: no entity configs (\"type\": Platform.*) inside {device} block", file=sys.stderr)
        return 2
    if added == 0:
        print(f"already patched: all {total} entity configs in {device} declare 'default'")
        return 0
    if args.dry_run:
        print(f"[dry-run] would add default=True to {added}/{total} entity configs in {device}")
        return 0

    args.backup_dir.mkdir(parents=True, exist_ok=True)
    backup = args.backup_dir / f"midea_devices.py.before_{device[2:].lower()}_default.{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    path.write_text(text[:start] + new_block + text[end:], encoding="utf-8")
    print(f"patched {added}/{total} entity configs in {device} block")
    print(f"backup: {backup}")
    print("restart Home Assistant to create the new entities")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
