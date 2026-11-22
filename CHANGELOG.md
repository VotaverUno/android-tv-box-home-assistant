# Changelog

## v0.3.0 (2026-11-22)

### Added
- 备份定时化：`scripts/stability/backup-schedule.sh`（runit 服务 `backup`）
  - 每周自动备份（保留最新 4 份）
  - 每月自动恢复演练：解压最新备份 → 校验 configuration.yaml / core.config_entries JSON / custom_components 数量
  - 演练结果写入 `drill-result`，失败推送告警
- 升级 Runbook：`scripts/stability/upgrade.sh`
  - `--preflight`：快照版本信息 + 补丁文件 + 全量配置备份
  - `--repatch`：自动重打 Android 平台 / DNS / 32 位垫片 / mobile_app / 美的 D9 补丁
  - `--verify`：17 项自检 + `check_config` + 等待 :8123 恢复
  - `--upgrade [ver]` / `--all [ver] --yes`（失败自动回滚）/ `--rollback [--dry-run]`
- 自检 14 → 17 项（备份新鲜度、备份调度服务、恢复演练结果）
- 新增文档 `docs/升级与恢复Runbook.md`

## v0.2.0 (2026-11-22)

## v0.2.0 (2026-11-22)

### Added
- 看门狗（L2/L3 落地）：`scripts/stability/watchdog.sh`
  - 8123 健康探测：每 60s 一次，连续 3 次失败触发重启，带 30 分钟冷却与 300s 启动宽限（防重启风暴）
  - 内存阈值：MemAvailable < 120MB 触发重启
  - 磁盘阈值：/data 剩余 < 2GB 时清理旧备份并告警
  - 状态机可测：`--selftest` / `--once` / `--status` / `--notify-test`（支持 dry-run）
- 异常推送：`scripts/stability/ha_notify.py`
  - 巴法云微信推送（HA 挂掉也能发；需在巴法云控制台绑定微信）
  - HA 常驻通知 + notify 实体（`notify.send_message`）；iOS 远程推送需 Nabu Casa
- 自检从 11 项扩展到 14 项（看门狗服务 / 日志新鲜度 / 状态文件）
- runit 服务：`watchdog`（与 hass 一起开机自启）

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