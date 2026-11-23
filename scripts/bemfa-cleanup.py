"""List Bemfa Cloud topics and delete the stale Home-Assistant generated ones.

Keeps exactly the topics listed in the bemfa_cloud integration options.
Only topics matching the HA pattern (ha + 12 hex + 3 digits) are considered,
so unrelated Bemfa devices are never touched.

Usage (run on the box, network required):
    python bemfa_cleanup.py [--dry-run]
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

STORAGE = Path(os.environ.get("HA_CONFIG", Path.home() / ".homeassistant")) / ".storage"
# HTTPS: the UID/openID is a secret (it controls every device on the account)
LIST_URL = "https://apis.bemfa.com/vb/api/v2/allTopic?{query}"
DELETE_URL = "https://pro.bemfa.com/v1/deleteTopic"
HA_TOPIC_RE = re.compile(r"^ha[0-9a-f]{12}\d{3}$")
TYPES = (7, 3)


def http_get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=25) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_post_json(url: str, payload: dict) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json; charset=utf-8"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    config_entries = json.loads((STORAGE / "core.config_entries").read_text(encoding="utf-8"))
    entry = next((e for e in config_entries["data"]["entries"] if e["domain"] == "bemfa_cloud"), None)
    if entry is None:
        print(f"ERROR: no bemfa_cloud config entry in {STORAGE / 'core.config_entries'}", file=sys.stderr)
        return 1
    uid = entry["data"]["uid"]
    keep = set(entry["options"]["config"].keys())
    print(f"keep ({len(keep)}):")
    for topic in sorted(keep):
        print("   ", topic, entry["options"]["config"][topic].get("name"))

    stale: list[tuple[int, str, str]] = []
    for topic_type in TYPES:
        try:
            query = urllib.parse.urlencode({"openID": uid, "type": topic_type})
            data = http_get_json(LIST_URL.format(query=query))
        except Exception as exc:  # noqa: BLE001
            print(f"list type={topic_type} failed: {type(exc).__name__}: {exc}")
            continue
        if data.get("code") != 0:
            print(f"list type={topic_type} code={data.get('code')} msg={data.get('msg')}")
            continue
        topics = data.get("data") or []
        print(f"list type={topic_type}: {len(topics)} topics")
        for item in topics:
            topic = item.get("topic", "")
            name = item.get("name", "")
            if HA_TOPIC_RE.match(topic) and topic not in keep:
                stale.append((topic_type, topic, name))

    print(f"\nstale HA topics to delete: {len(stale)}")
    deleted = 0
    for topic_type, topic, name in stale:
        if dry_run:
            print(f"   [dry-run] would delete type={topic_type} {topic} {name}")
            continue
        try:
            result = http_post_json(DELETE_URL, {"uid": uid, "topic": topic, "type": topic_type})
            ok = result.get("code") == 0
            print(f"   delete {topic} ({name}): {result.get('code')} {result.get('message') or result.get('msg')}")
            if ok:
                deleted += 1
        except Exception as exc:  # noqa: BLE001
            print(f"   delete {topic} failed: {type(exc).__name__}: {exc}")

    print(f"\ndeleted={deleted} of stale={len(stale)} (dry_run={dry_run})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
