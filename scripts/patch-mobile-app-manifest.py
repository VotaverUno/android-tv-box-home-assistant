#!/usr/bin/env python3
"""Remove the `cloud` dependency from Home Assistant's mobile_app integration.

Why: homeassistant/components/mobile_app/manifest.json lists "cloud" in
`after_dependencies`. When mobile_app is set up, HA therefore installs the cloud
integration's requirements as well (hass-nabucasa -> ... -> pydantic-core / jiter),
which need Rust and cannot be built on a 32-bit Android box. The install fails, mobile_app
never loads and the iPhone/Android companion app cannot connect (404 on /api/mobile_app).

Nabu Casa cloud is not used on this box, so dropping the (optional) after-dependency is
safe: mobile_app only uses cloud to create cloudhooks when cloud is actually configured.

Run with the venv Python (re-run after every Home Assistant upgrade):

    ~/ha-venv/bin/python patch-mobile-app-manifest.py           # patch
    ~/ha-venv/bin/python patch-mobile-app-manifest.py --check   # exit 0 if patched
    ~/ha-venv/bin/python patch-mobile-app-manifest.py --revert  # restore original
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REMOVE = ("cloud",)
BACKUP_SUFFIX = ".orig"


def find_manifest() -> Path:
    try:
        import importlib.util

        spec = importlib.util.find_spec("homeassistant")
        if spec and spec.origin:
            candidate = Path(spec.origin).parent / "components" / "mobile_app" / "manifest.json"
            if candidate.is_file():
                return candidate
    except Exception:  # noqa: BLE001 - fall back to sys.path scan
        pass
    for base in sys.path:
        candidate = Path(base) / "homeassistant" / "components" / "mobile_app" / "manifest.json"
        if candidate.is_file():
            return candidate
    raise SystemExit("mobile_app/manifest.json not found - run inside the HA venv")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="drop cloud from mobile_app dependencies")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="only report, exit 1 if unpatched")
    group.add_argument("--revert", action="store_true", help="restore the backed up original")
    parser.add_argument("--file", type=Path, help="explicit path to mobile_app/manifest.json")
    args = parser.parse_args(argv)

    path = args.file or find_manifest()
    backup = path.with_name(path.name + BACKUP_SUFFIX)

    if args.revert:
        if not backup.is_file():
            print("no backup found:", backup)
            return 1
        path.write_text(backup.read_text(encoding="utf-8"), encoding="utf-8")
        backup.unlink()
        print("reverted:", path)
        return 0

    text = path.read_text(encoding="utf-8")
    manifest = json.loads(text)
    found = {
        key: [d for d in manifest.get(key, []) if d in REMOVE]
        for key in ("after_dependencies", "dependencies")
    }
    if not any(found.values()):
        print("already patched (no cloud dependency):", path)
        return 0
    if args.check:
        print("NOT patched:", path, found)
        return 1

    for key, deps in found.items():
        if deps:
            manifest[key] = [d for d in manifest[key] if d not in REMOVE]
    if not backup.exists():
        backup.write_text(text, encoding="utf-8")
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("patched:", path, "removed:", {k: v for k, v in found.items() if v})
    print("backup: ", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
