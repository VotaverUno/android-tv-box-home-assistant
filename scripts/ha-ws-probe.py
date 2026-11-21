#!/usr/bin/env python3
"""Small helper: talk to the local Home Assistant WebSocket API.

Uses a refresh token from .storage/auth to mint an access token, then runs a command.
Useful for scripting entity/device registry changes without clicking the UI.

Usage:
    python ha-ws-probe.py list-entities <substring>
    python ha-ws-probe.py list-devices <substring>
    python ha-ws-probe.py rename <entity_id> <new name>
    python ha-ws-probe.py set-area <midea/other device unique id> <area_id>
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE_URL = "http://127.0.0.1:8123"
CONFIG = Path.home() / ".homeassistant"
AUTH_STORE = CONFIG / ".storage" / "auth"


def _owner_user_id() -> str:
    users = json.loads(AUTH_STORE.read_text(encoding="utf-8"))["data"]["users"]
    for user in users:
        if user.get("is_owner"):
            return user["id"]
    raise SystemExit("owner user not found")


def access_token() -> str:
    owner = _owner_user_id()
    tokens = json.loads(AUTH_STORE.read_text(encoding="utf-8"))["data"]["refresh_tokens"]
    now = time.time()
    candidates = [
        rt
        for rt in tokens
        if rt.get("user_id") == owner
        and rt.get("token_type") == "normal"
        and rt.get("token")
        and (rt.get("expire_at") is None or rt["expire_at"] > now + 3600)
    ]
    if not candidates:
        raise SystemExit("no valid refresh token found (log in to HA in a browser first)")
    candidates.sort(key=lambda rt: rt.get("last_used_at") or "", reverse=True)
    rt = candidates[0]
    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": rt["token"],
            "client_id": rt.get("client_id") or BASE_URL + "/",
        }
    ).encode()
    req = urllib.request.Request(
        BASE_URL + "/auth/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())["access_token"]


async def run(cmd: str, args: list[str]) -> None:
    import aiohttp

    token = access_token()
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect("ws://127.0.0.1:8123/api/websocket", timeout=25) as ws:
            await ws.receive_json()
            await ws.send_json({"type": "auth", "access_token": token})
            auth = await ws.receive_json()
            if auth.get("type") != "auth_ok":
                raise SystemExit(f"auth failed: {auth}")

            if cmd == "list-entities":
                needle = args[0]
                await ws.send_json({"id": 1, "type": "config/entity_registry/list"})
                entities = (await ws.receive_json()).get("result") or []
                for e in entities:
                    if needle in json.dumps(e, ensure_ascii=False):
                        print(e["entity_id"], "| name:", e.get("name"), "| device:", e.get("device_id"))
            elif cmd == "list-devices":
                needle = args[0]
                await ws.send_json({"id": 1, "type": "config/device_registry/list"})
                devices = (await ws.receive_json()).get("result") or []
                for d in devices:
                    if needle in json.dumps(d, ensure_ascii=False):
                        print(d.get("name"), "| id:", d.get("id"), "| area:", d.get("area_id"))
            elif cmd == "rename":
                entity_id, name = args[0], args[1]
                await ws.send_json(
                    {"id": 1, "type": "config/entity_registry/update", "entity_id": entity_id, "name": name}
                )
                print("rename:", (await ws.receive_json()).get("success"))
            elif cmd == "set-area":
                device_id, area_id = args[0], args[1]
                await ws.send_json(
                    {"id": 1, "type": "config/device_registry/update", "device_id": device_id, "area_id": area_id}
                )
                print("set-area:", (await ws.receive_json()).get("success"))
            else:
                raise SystemExit(f"unknown command: {cmd}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    asyncio.run(run(sys.argv[1], sys.argv[2:]))
