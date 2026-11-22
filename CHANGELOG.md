# Changelog

## v0.2.0 (2026-11-22)

> 本版本合并了原计划的 v0.2.0（看门狗）与 v0.3.0（备份调度 / 升级 Runbook）。

### Added — 看门狗（L2 / L3 自愈）
- `scripts/stability/watchdog.sh` + runit 服务 `watchdog`
  - 8123 健康探测：每 60s，连续 3 次失败触发重启，**30 分钟冷却 + 300s 启动宽限**（防重启风暴）
  - 内存阈值：`MemAvailable < 120MB` 触发重启
  - 磁盘阈值：`/data 剩余 < 2GB` 清理旧备份（保留最新 2 份）并告警
  - 状态机可测：`--selftest` / `--once` / `--status` / `--notify-test`，支持 `WD_DRY_RUN=1`
- 通知助手 `scripts/stability/ha_notify.py`
  - **巴法云微信推送**（HA 挂掉也能发；需在巴法云控制台绑定微信）
  - HA 常驻通知 + `notify.send_message` 实体；iOS 远程推送需 Nabu Casa（已文档化）

### Added — 洗衣机程序控制
- 美的 D9（小洗衣机双筒）：新增 `select.*_db_program` / `select.*_dc_program`（78 / 31 个程序）与 4 个启动/暂停按钮
  - 补丁：`scripts/patch-d9-programs.py`（幂等，升级 midea_ac_lan 后需重打；已并入 `upgrade.sh --repatch`）
- 海尔滚筒洗衣机：程序/水温/转速 select+number 实体原本已存在，新增 5 个封装脚本（选程序/启动/暂停/水温/转速）
- 新增 11 个 HA 脚本：`script.haier_wash_*`、`script.d9_washer_*`、`script.d9_dryer_*`
- 新增文档 `docs/洗衣机程序控制.md`（程序名中英对照、Lovelace 卡片、小爱桥接方案）
- 实测：D9 `db_program` 设置为 `underwear` 成功回读

### Added — 备份定时化
- `scripts/stability/backup-schedule.sh` + runit 服务 `backup`
  - **每周**自动备份（保留最新 4 份）
  - **每月**自动恢复演练：解压最新备份 → 校验 `configuration.yaml` 顶层键 → 校验 `.storage/core.config_entries` JSON → 校验 `custom_components` ≥1
  - 演练结果写入 `drill-result`；失败自动推送告警
  - 手动触发：`--force-backup` / `--force-drill` / `--status`

### Added — 升级 Runbook
- `scripts/stability/upgrade.sh`
  - `--preflight`：记录 HA/Python 版本与 pip freeze、快照 5 类补丁文件、全量配置备份
  - `--repatch`：自动重打 Android 平台放行、sitecustomize DNS、32 位垫片（缺则重装）、mobile_app manifest、美的 D9
  - `--verify`：17 项自检 + `hass --script check_config` + 等待 :8123 恢复（最多 3 分钟）
  - `--upgrade [ver]` / `--all [ver] --yes`（失败自动回滚）/ `--rollback [--dry-run]`
- 新增文档 `docs/升级与恢复Runbook.md`

### Tests
- 自检 11 → **17 项**：新增 T15 备份新鲜度、T16 备份调度服务、T17 恢复演练结果
- 实测：`pass=17 fail=0`；恢复演练 PASS；preflight/verify/rollback dry-run 均通过

### Fixed
- 看门狗 `disk_free` 在 Toybox `df`（不支持 `-m`）下返回空 → 改用 `df -Pk` 换算
- 恢复演练不能用 `yaml.safe_load` 解析 `configuration.yaml`（含 HA 专用 `!include` 标签）→ 改用 config_entries JSON + 关键字校验

### Known limitations
- iOS 远程推送需 Nabu Casa；否则只能收到 HA 常驻通知
- 巴法云微信推送需先在控制台绑定微信
- armv7 已被 HA 官方淘汰：请锁定版本，升级前务必 `upgrade.sh --preflight`

## v0.1.0 (2026-11-21)
