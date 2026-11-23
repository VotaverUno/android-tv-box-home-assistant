# Changelog

## v0.2.0 (2026-11-22)

> This release merges the originally planned v0.2.0 (watchdog) and v0.3.0 (backup scheduler / upgrade runbook).

### Added — Watchdog (L2 / L3 self-healing)
- `scripts/stability/watchdog.sh` + runit service `watchdog`
  - :8123 health probe every 60 s; restart after 3 consecutive failures, with **30-minute cooldown + 300 s startup grace** (prevents restart storms)
  - memory threshold: `MemAvailable < 120MB` triggers a restart
  - disk threshold: `/data free < 2GB` prunes old backups (keeps latest 2) and alerts
  - testable state machine: `--selftest` / `--once` / `--status` / `--notify-test`, supports `WD_DRY_RUN=1`
- Notification helper `scripts/stability/ha_notify.py`
  - **Bemfa WeChat push** (works even when HA is down; requires binding WeChat in the Bemfa console)
  - HA persistent notification + `notify.send_message` entities; iOS remote push needs Nabu Casa (documented)

### Added — Washer program control
- Midea D9 (dual-drum mini washer): new `select.*_db_program` / `select.*_dc_program` (78 / 31 programs) and 4 start/pause buttons
  - patch: `scripts/patch-d9-programs.py` (idempotent; must be re-applied after upgrading midea_ac_lan; wired into `upgrade.sh --repatch`)
- Haier front-load washer: program/temperature/spin select+number entities already existed; added 5 wrapper scripts (select program / start / pause / temperature / spin)
- 11 new HA scripts: `script.haier_wash_*`, `script.d9_washer_*`, `script.d9_dryer_*`
- New doc `docs/洗衣机程序控制.md` (program name mapping, Lovelace card, voice bridge) — superseded by the merged appliance doc later
- Tested: D9 `db_program` set to program A (156) reads back successfully

### Changed — Simplified UI (per user request)
- New one-tap scripts: `script.haier_smart_wash` (smart wash), `script.dishwasher_standard`, `script.dishwasher_standard_start` (Standard), `script.d9_wash_program_a` (cloud program 156), `script.d9_wash_program_b` (cloud program 148); setting the program auto-selects the matching drum; new "auto dry after wash" parameter (TLV 0x06 `db060101`), order: set program → enable dry → start
- **All functional switches kept** (power, loosen, fresh air, child lock, auto-dosing, anti-allergy, care, SPA, anti-crease, steam, photo-plasma, voice, auto-door, …)
- Removed stale unavailable entities (old D9 program sensors) and disabled Haier's 10 redundant program-select selects in the registry (re-enableable)

### Fixed
- D9 mini washer: switched to combined TLV records for "drum + program/dry/start", fixing programs landing in the wrong drum (tested)
- Haier one-tap smart wash: changed to "keep powered → set program → wait for state confirmation → start", fixing the old-program (single spin) start issue

### Docs
- Combined docs: "Appliance control & voice troubleshooting" now covers virtual switches → Bemfa sync → device setup → troubleshooting → model adaptation methodology (replaces three older docs)
- Added "Voice control & troubleshooting summary": Xiaoai virtual switches, Haier program order, D9 drum combination, Bemfa sync list, troubleshooting toolbox
- Added "Appliance adaptation methodology": how to capture program IDs / dry fields / drum location per model; includes D9/E1/Haier test matrix

### Added — Dishwasher program control
- Dishwasher (Midea E1): existing `select.program` / `select.mode_select` (27 modes incl. `auto_wash`, `eco_wash`, `strong_wash`) + 5 buttons
- 8 new wrapper scripts: `script.dishwasher_mode_start` (select-and-start), `dishwasher_program`, `dishwasher_start/pause/resume/cancel`, `dishwasher_delay`, `dishwasher_start_delayed`
- **Limitation**: dry duration (`dry_set_min`) has no corresponding byte in the local `MessageWork` protocol — readable only, not writable; use `wash_dry`/`single_dry` programs instead (documented)

### Added — Scheduled backups
- `scripts/stability/backup-schedule.sh` + runit service `backup`
  - **weekly** automatic backup (keeps latest 4)
  - **monthly** restore drill: extract latest backup → validate `configuration.yaml` top-level keys → validate `.storage/core.config_entries` JSON → validate `custom_components` ≥ 1
  - drill result written to `drill-result`; failures trigger alerts
  - manual triggers: `--force-backup` / `--force-drill` / `--status`

### Added — Upgrade runbook
- `scripts/stability/upgrade.sh`
  - `--preflight`: record HA/Python versions and pip freeze, snapshot 5 patch files, full config backup
  - `--repatch`: re-apply Android platform, sitecustomize DNS, 32-bit shims (reinstall if missing), mobile_app manifest, Midea D9
  - `--verify`: 17-check self-test + `hass --script check_config` + wait for :8123 (max 3 min)
  - `--upgrade [ver]` / `--all [ver] --yes` (auto rollback on failure) / `--rollback [--dry-run]`
- New doc `docs/升级与恢复Runbook.md`

### Tests
- Self-test 11 → **17 checks**: added T15 backup freshness, T16 backup scheduler service, T17 restore drill result
- Tested: `pass=17 fail=0`; restore drill PASS; preflight/verify/rollback dry-run all pass

### Fixed
- Watchdog `disk_free` returned empty with Toybox `df` (no `-m` support) → switched to `df -Pk` conversion
- Restore drill couldn't parse `configuration.yaml` with `yaml.safe_load` (HA-specific `!include` tags) → switched to config_entries JSON + keyword validation

### Known limitations
- iOS remote push requires Nabu Casa; otherwise you only get HA persistent notifications
- Bemfa WeChat push requires binding WeChat in the console first
- armv7 has been dropped by HA upstream: pin versions and always run `upgrade.sh --preflight` before upgrading

## v0.1.0 (2026-11-21)
