# Changelog

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