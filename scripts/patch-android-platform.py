#!/usr/bin/env python3
"""Allow Home Assistant Core to start on Android/Termux.

Home Assistant refuses to run on platforms other than Linux/macOS/WSL:

    if not sys.platform.startswith(("darwin", "linux")):
        print("Home Assistant only supports Linux, OSX and Windows using WSL", ...)
        sys.exit(1)

Termux reports sys.platform == "android", so patch that check to accept it.
Run with the venv Python that has Home Assistant installed (re-run after every
Home Assistant upgrade, pip overwrites the file):

    ~/ha-venv/bin/python patch-android-platform.py           # patch
    ~/ha-venv/bin/python patch-android-platform.py --check   # exit 0 if patched
    ~/ha-venv/bin/python patch-android-platform.py --revert  # restore original
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# tolerate whitespace / quote style differences between HA versions
CHECK_RE = re.compile(
    r"""if\s+not\s+sys\.platform\.startswith\(\s*\(\s*(?P<items>[^)]*?)\s*\)\s*\)\s*:"""
)
BACKUP_SUFFIX = ".orig"


def find_main() -> Path:
    """Locate homeassistant/__main__.py inside the active Python environment."""
    try:
        import importlib.util

        spec = importlib.util.find_spec("homeassistant")
        if spec and spec.origin:
            candidate = Path(spec.origin).with_name("__main__.py")
            if candidate.is_file():
                return candidate
    except Exception:  # noqa: BLE001 - fall back to sys.path scan
        pass
    for base in sys.path:
        candidate = Path(base) / "homeassistant" / "__main__.py"
        if candidate.is_file():
            return candidate
    raise SystemExit("homeassistant/__main__.py not found - run inside the HA venv")


def _platforms(items: str) -> list[str]:
    return re.findall(r"""["']([^"']+)["']""", items)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="allow Home Assistant on Android/Termux")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="only report, exit 1 if unpatched")
    group.add_argument("--revert", action="store_true", help="restore the backed up original")
    parser.add_argument("--file", type=Path, help="explicit path to homeassistant/__main__.py")
    args = parser.parse_args(argv)

    path = args.file or find_main()
    backup = path.with_name(path.name + BACKUP_SUFFIX)  # homeassistant/__main__.py.orig

    if args.revert:
        if not backup.is_file():
            print("no backup found:", backup)
            return 1
        path.write_text(backup.read_text(encoding="utf-8"), encoding="utf-8")
        backup.unlink()
        print("reverted:", path)
        return 0

    text = path.read_text(encoding="utf-8")
    match = CHECK_RE.search(text)
    if match is None:
        print("WARNING: expected platform check not found; inspect manually:", path)
        # newer HA may have removed the check entirely - that is not an error for --check
        return 1
    platforms = _platforms(match.group("items"))
    if "android" in platforms:
        print("already patched:", path)
        return 0
    if args.check:
        print("NOT patched:", path)
        return 1

    new_items = ", ".join(f'"{p}"' for p in [*platforms, "android"])
    replacement = f"if not sys.platform.startswith(({new_items})):"
    if not backup.exists():
        backup.write_text(text, encoding="utf-8")
    path.write_text(text[: match.start()] + replacement + text[match.end() :], encoding="utf-8")
    print("patched:", path)
    print("backup: ", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
