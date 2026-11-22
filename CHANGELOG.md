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

## v0.1.0 (2026-11-21)

### Added
- 中文完整教程（12 章）+ 新手 12 卡点 + 求助指南
- English Getting Started guide
- 架构说明：角色分工、总体架构、语音/美的局域网时序、12 项程序改造清单、5 层看门狗设计
- 脚本（11 个）：
  - `shims-32bit.py`：32 位 armv7 纯 Python 垫片（orjson / ulid-transform / fnv-hash-fast / uv）
  - `patch-android-platform.py`：放行 HA 的 Android 平台检查
  - `sitecustomize.py`：修复 Android pycares DNS 缺陷
  - `patch-midea-d9-default.py`：修复美的 D9 复式洗烘一体机实体 bug
  - `start-ha.sh` + `stability/runit-setup.sh`：启动与 runit 守护
  - `stability/backup-ha.sh` / `selftest.sh` / `rollback.sh`：备份、自检、回滚
  - `bemfa-cleanup.py`：巴法云设备批量清理
  - `ha-ws-probe.py`：HA WebSocket 脚本化工具
- 实拍验证截图（8 张）+ Social preview 图
- Issue / PR 模板、CONTRIBUTING

### Notes
- 实测环境：小米盒子 MDZ-26-AA（32 位 armv7、2GB 内存、Android 9），Home Assistant 2026.11.1
- 启动 40~90 秒，连续运行 5 天+