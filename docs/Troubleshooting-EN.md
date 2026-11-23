# Troubleshooting (English)

> This is the English quick reference for the most common problems in this project.
> It covers **HA Core on Android/Termux**, the 32-bit (armv7) workarounds, integrations,
> the voice bridge, and 24/7 operation.
>
> Chinese detail lives in [`教程-安卓盒子装HomeAssistant.md`](教程-安卓盒子装HomeAssistant.md) and
> [`家电控制与语音排错.md`](家电控制与语音排错.md).

---

## 0. Before anything else

This project is an **unsupported installation**:

- Home Assistant no longer supports 32-bit / armv7 installations (HAOS and Container are 64-bit only).
- HA Core here runs in a **Termux Python venv**, with small patches to HA core code.
- **Every HA upgrade must be re-patched** — use `scripts/stability/upgrade.sh`.

If a problem is not listed here, don't assume the setup is broken: the hardware itself
(2 GB RAM, eMMC, armv7) is the limiting factor.

---

## 1. Termux / installation

### `pip install` tries to compile Rust/C packages and hangs

There are no armv7 wheels for `orjson`, `ulid-transform`, `fnv-hash-fast` and `uv`.
Install the pure-Python stand-ins **before** installing HA:

```bash
python scripts/shims-32bit.py
```

### HA exits immediately: "Home Assistant only supports Linux, macOS, Windows"

`homeassistant/__main__.py` checks `sys.platform`; Termux reports `android`.

```bash
~/ha-venv/bin/python scripts/patch-android-platform.py        # patch
~/ha-venv/bin/python scripts/patch-android-platform.py --check   # verify
```

Re-run after every HA upgrade.

### Cloud logins fail: "Could not contact DNS servers"

On this Android build `pycares.getaddrinfo()` returns `ENOTIMP`. The fix is the
`sitecustomize.py` DNS shim (routes `aiohttp.AsyncResolver.resolve` through the
system resolver on Android only).

```bash
cp scripts/sitecustomize.py ~/ha-venv/lib/python3.14/site-packages/sitecustomize.py
~/ha-venv/bin/python -c "import sitecustomize; print(sitecustomize.STATUS)"
# expected: patched
```

### Startup is very slow (minutes)

Trim the config: remove `default_config`, keep `recorder` minimal or disabled.
On the reference box this changed cold start from **~361 s to ~39 s**.
Also disable unused TV-box apps so they don't compete for RAM.

### ImportError: cryptography `_rust.abi3.so` / pip tries to build cryptography

`cryptography` is a Rust extension and **must** come from a real binary. On Termux:

```bash
pkg install -y python-cryptography
~/ha-venv/bin/python -c "import cryptography; print(cryptography.__version__, cryptography.__file__)"
```

The venv must be created with `--system-site-packages` so it inherits the Termux package.
Never write a fake `cryptography` shim: it would break TLS/token handling at runtime instead of
failing fast.

### HA starts, but some entities are missing

Check `~/.homeassistant/home-assistant.log` (or `~/ha.log` in this setup) for:

- `Configuring the template integration under the switch platform key is not supported`
  → use the modern `template:` syntax (see below).
- integration-specific errors (`Cannot connect`, `auth failed`, `No supported query protocol`).

---

## 2. Integrations

### Midea devices: "Unable to connect" forever

Check in this order:

1. `ping <device-ip>` and `nc -z <device-ip> 6444`;
2. The device may use a **different protocol generation** (v2 vs v3). Some models answer
   v2 but do not support the v2 query protocol; newer models reject v3 authentication.
   This is not fixable with config — currently such models are unsupported.
3. Only do a **cloud login once** to fetch token/key; repeated logins may trigger the
   vendor's risk control.

### Midea D9 washer: device is polled but has 0 entities

The D9 entity definitions in `midea_ac_lan` are missing `"default": True`.
Run:

```bash
~/ha-venv/bin/python scripts/patch-midea-d9-default.py
```

### `mobile_app` returns 404 / companion app can't connect

`mobile_app` lists `cloud` as an after-dependency, which pulls Rust/micro-VAD
dependencies that cannot build on armv7. Remove it from the manifest:

```bash
~/ha-venv/bin/python scripts/patch-mobile-app-manifest.py
```

### Haier: program changed but the old program starts

Cloud writes are **asynchronous**, and a powered-off device ignores program writes.
Correct order: keep powered → set program → **wait until the program state is the target**
→ start. See `script.haier_smart_wash` in `scripts/examples/`.

### Bemfa: entity name / device count issues

Bemfa has a device-name length limit — keep names short. It cannot sync
`script`/`select` entities; use template switches that call a script.

---

## 3. Voice bridge (Xiao Ai via Bemfa)

Checklist:

1. The 4 template switches exist in HA (`switch.xiaoi_*` or your own names);
2. They are **checked** in the Bemfa integration config (not the scripts);
3. Mi Home → 其他平台设备 → Bemfa: unbind/rebind so the new devices appear;
4. Say the switch name (short names work best).

`Template switch state is unknown`: make the state template return a literal
(`"{{ false }}"` renders as `False`, which some sync flows dislike — use `"off"`).

A script being visible in HA but not in Mi Home is expected: Bemfa only syncs
switch/sensor/climate/cover/light/fan/water_heater domains.

---

## 4. 24/7 operation

| Symptom | Cause | Fix |
|---|---|---|
| HA web UI opens in ~20 s after `kill -9` | This is expected (runit supervision) | No action; if more than a minute, check `sv status hass` |
| Repeated restarts / restart storm | Watchdog restarts while HA is still booting | Keep the **300 s startup grace** and **30 min cooldown** (see `scripts/stability/watchdog.sh`) |
| Disk fills up | Logs/backups grow | Log rotation + weekly backup prune (keep 4) in `scripts/stability/backup-schedule.sh` |
| Memory pressure | 2 GB is tight | Restart on low memory threshold; disable unused integrations |
| Device stopped responding after an upgrade | Core patches were overwritten by pip | `scripts/stability/upgrade.sh --repatch` |
| `selftest.sh` fails after upgrade | Missing patch/backup/drill | Read the failing `T*` check; rerun `--repatch` and `--verify` |

Useful commands on the box:

```bash
tail -50 ~/ha.log
sv status hass
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8123/
python -m homeassistant --script check_config -c ~/.homeassistant
scripts/stability/selftest.sh
scripts/stability/upgrade.sh --verify
```

---

## 5. Known limitations (by design)

- 32-bit armv7 is EOL: no official support, patches required on every upgrade.
- Some Midea device generations do not expose local LAN control at all.
- Battery-powered cameras (e.g. peephole cameras) usually have no usable local RTSP stream;
  expect sensors/PIR events rather than live video.
- The voice path depends on third-party clouds (Bemfa / Midea / Haier).
- Auto-start after a real power cut is still being verified.

---

## 6. How to get help

Open an issue with:

1. box model, CPU architecture, RAM, Android version;
2. HA version and install method;
3. the exact command you ran and the full error;
4. relevant log lines (remove IPs/tokens/accounts first).

Please don't paste tokens, account passwords, or device IDs.
