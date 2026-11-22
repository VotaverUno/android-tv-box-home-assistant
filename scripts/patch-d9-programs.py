#!/usr/bin/env python3
"""Patch midea_ac_lan for Midea D9 (washer-dryer combo) program control.

What it does (idempotent):
1. Converts ``db_program`` / ``dc_program`` sensors into **select** entities
   backed by the device's ``_db_program`` / ``_dc_program`` option dicts.
2. Adds start/pause **buttons** for both buckets (db = washer/left, dc = dryer/right).
3. Drops the inherited ``translation_key`` on the new entities so the configured
   English ``name`` is used even when no translation entry exists.

Run with the HA venv python (paths assume the standard Termux HA install):

    ~/ha-venv/bin/python scripts/patch-d9-programs.py
    ~/ha-venv/bin/python -m py_compile <component>/midea_devices.py
    sv restart hass
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

DEVICES = Path(
    "/data/data/com.termux/files/home/.homeassistant/custom_components/"
    "midea_ac_lan/midea_devices.py"
)
SNAP = Path("/data/data/com.termux/files/home/stability/snapshots")


def select_block(attr: str, options_dict: str, name: str, icon: str) -> str:
    return f'''            D9Attributes.{attr}: {{
                "type": Platform.SELECT,
                "default": True,
                "name": "{name}",
                "icon": "{icon}",
                "options_dict": "{options_dict}",
            }},'''


def button_block(key: str, attr: str, press: bool, name: str, icon: str) -> str:
    return f'''            "{key}": {{
                "type": Platform.BUTTON,
                "default": True,
                "name": "{name}",
                "icon": "{icon}",
                "attribute": "{attr}",
                "press_value": {press},
            }},'''


def main() -> int:
    if not DEVICES.exists():
        print("midea_devices.py not found:", DEVICES)
        return 1
    src = DEVICES.read_text(encoding="utf-8")
    if '"options_dict": "_db_program"' in src:
        print("already patched (options_dict present)")
        return 0

    SNAP.mkdir(parents=True, exist_ok=True)
    backup = SNAP / "midea_devices.py.before_d9_select"
    if not backup.exists():
        shutil.copy2(DEVICES, backup)
        print("backup:", backup)

    for attr, options, name, icon in (
        ("db_program", "_db_program", "Washer Program", "mdi:washing-machine"),
        ("dc_program", "_dc_program", "Dryer Program", "mdi:tumble-dryer"),
    ):
        pat = re.compile(
            r"\n[ \t]*D9Attributes\." + attr + r":\s*\{.*?\n[ \t]*\},", re.S
        )
        src, n = pat.subn("\n" + select_block(attr, options, name, icon), src, count=1)
        if n != 1:
            print("pattern not found for", attr)
            return 1

    buttons = (
        "\n"
        + button_block("db_start", "db_running_status", True, "Washer Start", "mdi:play")
        + button_block("db_pause", "db_running_status", False, "Washer Pause", "mdi:pause")
        + button_block("dc_start", "dc_running_status", True, "Dryer Start", "mdi:play")
        + button_block("dc_pause", "dc_running_status", False, "Dryer Pause", "mdi:pause")
    )
    dc_pat = re.compile(r"(D9Attributes\.dc_program:\s*\{.*?\n[ \t]*\},)", re.S)
    src, n = dc_pat.subn(lambda m: m.group(1) + buttons, src, count=1)
    if n != 1:
        print("dc_program block not found for button insertion")
        return 1

    DEVICES.write_text(src, encoding="utf-8")
    print("patched: db_program/dc_program -> SELECT, 4 start/pause buttons added")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
