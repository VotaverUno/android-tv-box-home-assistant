#!/usr/bin/env python3
"""Allow Home Assistant Core to start on Android/Termux.

Home Assistant refuses to run on platforms other than Linux/macOS/WSL:

    if not sys.platform.startswith(("darwin", "linux")):
        print("Home Assistant only supports Linux, OSX and Windows using WSL", ...)
        sys.exit(1)

Termux reports sys.platform == "android", so patch that check to accept it.
Run with the venv Python that has Home Assistant installed:

    ~/ha-venv/bin/python patch-android-platform.py
"""

from __future__ import annotations

import sys
from pathlib import Path

TARGET = Path(__file__).resolve().parent  # placeholder, replaced below


def find_main() -> Path:
    """Locate homeassistant/__main__.py inside the active Python environment."""
    for base in sys.path:
        candidate = Path(base) / "homeassistant" / "__main__.py"
        if candidate.is_file():
            return candidate
    raise SystemExit("homeassistant/__main__.py not found - run inside the HA venv")


def main() -> int:
    path = find_main()
    text = path.read_text(encoding="utf-8")
    old = 'if not sys.platform.startswith(("darwin", "linux")):'
    new = 'if not sys.platform.startswith(("darwin", "linux", "android")):'
    if new in text:
        print("already patched:", path)
        return 0
    if old not in text:
        print("WARNING: expected platform check not found; inspect manually:", path)
        return 1
    if not (path.parent.parent / "__main__.py.orig").exists():
        (path.parent.parent / "__main__.py.orig").write_text(text, encoding="utf-8")
    path.write_text(text.replace(old, new), encoding="utf-8")
    print("patched:", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
