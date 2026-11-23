# Box compatibility list (PRs welcome)

> Tested box models that pass/fail. Porting to a new box: see [Porting Guide](Porting-Guide-EN.md). To contribute, add a row in the format below and open a PR.

| Model | CPU arch | RAM | Android | Status | Notes |
|---|---|---|---|---|---|
| Xiaomi Mi Box 4S Pro (MDZ-26-AA) | armv7 (32-bit) | 2GB | 9 | ✅ tested | source device of this project; cold start 40–90 s |
| Your box | armv7 / arm64 | ? GB | ? | ✅ / ⚠️ / ❌ | notes |

## Legend

- ✅ pass: Termux installs, HA starts, web UI reachable
- ⚠️ partial: starts but RAM is tight / some features fail
- ❌ fail: Termux won't install / HA won't start

## Check commands (in Termux on the box)

```bash
uname -m
getprop ro.build.version.release
free -m
df -h /data
```
