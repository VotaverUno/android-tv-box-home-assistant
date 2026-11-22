#!/data/data/com.termux/files/home/ha-venv/bin/python
"""Send a notification from the box (watchdog / scripts).

Usage: ha_notify.py "<title>" "<message>"

Channels (all best-effort):
1. Bemfa WeChat push  (works even when Home Assistant is down; uid read from HA config entry)
2. HA persistent notification
3. HA notify entities via notify.send_message (companion app / notify platforms)
4. Legacy notify.mobile_app_* services (older HA)
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
BASE = "http://127.0.0.1:8123"
STORE = HOME / ".homeassistant" / ".storage"
BEMFA_URL = "https://apis.bemfa.com/vb/wechat/v1/wechatAlertJson"
BEMFA_DEVICE = "HomeAssistant"


def _post(url: str, payload: dict, headers: dict, timeout: int = 12):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def bemfa_wechat(title: str, message: str) -> bool:
    """Push to WeChat via Bemfa (requires WeChat bound in Bemfa console)."""
    try:
        entries = json.loads((STORE / "core.config_entries").read_text(encoding="utf-8"))
        uid = ""
        for entry in entries["data"]["entries"]:
            if entry.get("domain") == "bemfa_cloud":
                uid = entry.get("data", {}).get("uid", "")
                break
        if not uid:
            print("bemfa_wechat: no bemfa_cloud entry, skipped")
            return False
        raw = _post(
            BEMFA_URL,
            {"uid": uid, "device": BEMFA_DEVICE, "message": f"{title}: {message}"},
            {"Content-Type": "application/json; charset=utf-8"},
        )
        result = json.loads(raw.decode())
        ok = result.get("code") == 0
        print("bemfa_wechat:", "ok" if ok else f"fail {result}")
        return ok
    except Exception as exc:  # noqa: BLE001
        print("bemfa_wechat: fail", exc)
        return False


def access_token() -> str:
    data = json.loads((STORE / "auth").read_text(encoding="utf-8"))["data"]
    owner = next(u["id"] for u in data["users"] if u.get("is_owner"))
    now = time.time()
    candidates = [
        rt for rt in data["refresh_tokens"]
        if rt.get("user_id") == owner
        and rt.get("token_type") == "normal"
        and rt.get("token")
        and (rt.get("expire_at") is None or rt["expire_at"] > now + 3600)
    ]
    if not candidates:
        raise SystemExit("no valid refresh token")
    candidates.sort(key=lambda rt: rt.get("last_used_at") or "", reverse=True)
    rt = candidates[0]
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": rt["token"],
        "client_id": rt.get("client_id") or BASE + "/",
    }).encode()
    req = urllib.request.Request(
        BASE + "/auth/token", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())["access_token"]


def call(token: str, path: str, payload=None):
    req = urllib.request.Request(
        BASE + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        method="GET" if payload is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.status, resp.read()


def ha_channels(title: str, message: str) -> int:
    ok = 0
    try:
        token = access_token()
    except Exception as exc:  # noqa: BLE001
        print("ha channels: skipped (HA down / token fail)", exc)
        return ok
    try:
        call(token, "/api/services/persistent_notification/create",
             {"title": title, "message": message})
        ok += 1
        print("persistent_notification: ok")
    except Exception as exc:  # noqa: BLE001
        print("persistent_notification: fail", exc)

    try:
        _, raw = call(token, "/api/states")
        notify_entities = [
            s["entity_id"] for s in json.loads(raw.decode())
            if s["entity_id"].startswith("notify.")
        ]
        for entity in sorted(notify_entities):
            try:
                call(token, "/api/services/notify/send_message",
                     {"entity_id": entity, "title": title, "message": message})
                print("notify.send_message -> " + entity + ": ok")
                ok += 1
            except Exception as exc:  # noqa: BLE001
                print("notify.send_message -> " + entity + ": fail", exc)
    except Exception as exc:  # noqa: BLE001
        print("notify entity discovery failed", exc)

    try:
        _, raw = call(token, "/api/services")
        targets = []
        for svc in json.loads(raw.decode()):
            if svc.get("domain") == "notify":
                targets.extend(
                    name for name in (svc.get("services") or {})
                    if name.startswith("mobile_app_")
                )
        for target in sorted(targets):
            try:
                call(token, "/api/services/notify/" + target,
                     {"title": title, "message": message})
                print("notify." + target + ": ok")
                ok += 1
            except Exception as exc:  # noqa: BLE001
                print("notify." + target + ": fail", exc)
    except Exception as exc:  # noqa: BLE001
        print("legacy notify discovery failed", exc)
    return ok


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: ha_notify.py <title> <message>")
        return 2
    title, message = sys.argv[1], sys.argv[2]
    ok = 1 if bemfa_wechat(title, message) else 0
    ok += ha_channels(title, message)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
