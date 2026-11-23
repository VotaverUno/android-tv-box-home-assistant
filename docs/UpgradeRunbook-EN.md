# Upgrade & Recovery Runbook

> For this box (32-bit armv7 + Termux + HA Core venv).
> All commands run inside Termux on the box. **Always run preflight first (it creates a backup).**

---

## 0. The three scripts

| Script | Purpose |
|---|---|
| `~/stability/scripts/backup-schedule.sh` | weekly automatic backup + monthly restore drill (runit service `backup`) |
| `~/stability/scripts/upgrade.sh` | upgrade runbook: preflight / repatch / verify / upgrade / rollback |
| `~/stability/scripts/selftest.sh` | 17-check health self-test |

---

## 1. Scheduled backups (already live)

### Behavior
- runit service `backup` runs persistently, checks hourly;
- **weekly** (≥7 days): runs `backup-ha.sh`, keeps the latest 4 copies;
- **monthly** (≥30 days): performs a **restore drill**:
  1. extract the latest backup to a temp dir;
  2. verify `configuration.yaml` exists and contains `homeassistant:`;
  3. verify `.storage/core.config_entries` is valid JSON;
  4. verify `custom_components` count ≥ 1;
  5. result written to `~/stability/backup-schedule/drill-result`; failures trigger an alert.

### Common commands
```bash
# manual trigger (does not affect production data)
bash ~/stability/scripts/backup-schedule.sh --force-backup
bash ~/stability/scripts/backup-schedule.sh --force-drill

# status
bash ~/stability/scripts/backup-schedule.sh --status
sv status backup
cat ~/stability/backup-schedule/drill-result
tail -n 20 ~/stability/logs/backup-schedule.log
```

---

## 2. Upgrade runbook

### 2.1 Before upgrading: preflight (mandatory)

```bash
bash ~/stability/scripts/upgrade.sh --preflight
```

It will:
1. create a snapshot dir `~/stability/upgrades/<timestamp>/`;
2. record current **HA version / Python version / pip freeze**;
3. back up **patched files** (sitecustomize, HA `__main__.py`, `midea_devices.py`, mobile_app manifest; re-applied via repo scripts `patch-android-platform.py`, `patch-midea-d9-default.py`, `patch-mobile-app-manifest.py`, `shims-32bit.py`, `stability/scripts/patch-d9-programs.py`);
4. full config backup (tar; path stored in `backup.txt` in the snapshot dir).

### 2.2 Upgrade + repatch + verify (one command)

```bash
# upgrade to latest (add --yes for automatic rollback on failure)
bash ~/stability/scripts/upgrade.sh --all --yes

# or pin a version
bash ~/stability/scripts/upgrade.sh --all 2026.12.0 --yes
```

Flow: `preflight → repatch → pip install → restart → verify`.

**verify checks three things**:
1. `selftest.sh` — all 17 checks PASS;
2. `hass --script check_config` passes;
3. wait for `:8123` to come back (max 3 minutes).

### 2.3 Step by step (manual control)

```bash
bash ~/stability/scripts/upgrade.sh --preflight     # backup + snapshot
bash ~/stability/scripts/upgrade.sh --repatch       # only re-apply patches
bash ~/stability/scripts/upgrade.sh --upgrade       # only upgrade (latest if omitted)
bash ~/stability/scripts/upgrade.sh --verify        # only verify
```

### 2.4 If the upgrade fails: rollback

```bash
# dry run first
bash ~/stability/scripts/upgrade.sh --rollback --dry-run

# real rollback (restore config + reinstall old version + repatch + verify)
bash ~/stability/scripts/upgrade.sh --rollback
```

Rollback uses the most recent preflight snapshot: `pip-homeassistant.txt` (old version) and
`backup.txt` (config backup path).

### 2.5 Patches that must be checked (overwritten by upgrades)

| Patch | Failure symptom | How to re-apply |
|---|---|---|
| Android platform allow-list | HA exits: `Home Assistant only supports Linux...` | `--repatch` (automatic) |
| sitecustomize DNS | cloud logins fail: `Could not contact DNS servers` | `--repatch` (automatic) |
| 32-bit shims | JSON/import errors at startup | `--repatch` (checks and reinstalls if missing) |
| mobile_app manifest | phone app can't connect (404) | `--repatch` (automatic) |
| Midea D9 default entities | D9 washer shows 0 entities | `--repatch` (automatic) |

> `--repatch` automates all of the above; still sanity-check the log afterwards:
> `grep -iE "error|exception" ~/ha.log | tail`.

---

## 3. Upgrade logs and checks

```bash
tail -n 60 ~/stability/logs/upgrade.log
ls -1t ~/stability/upgrades/ | head -3
cat ~/stability/upgrades/last
```

After a successful upgrade:
1. restart the phone app and confirm it connects;
2. spot-check Midea/Haier device states;
3. test one Xiaoai voice command;
4. add an entry to `CHANGELOG` in the repo.

---

## 4. FAQ

| Problem | Fix |
|---|---|
| HA won't start after upgrade | `--rollback` (uses the latest snapshot) |
| Many entities unavailable after upgrade | check `ha.log`; usually a lost patch → `--repatch` |
| pip install hangs | verify the mirror in `~/pip.conf`; retry `--upgrade` |
| Out of disk | `df -h /data`; old backups are pruned automatically (4 kept) |
| Want to pin versions (no auto upgrade) | don't run `--upgrade`; apt/pip never upgrade automatically here |
