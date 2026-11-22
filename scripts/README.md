# scripts 说明

所有脚本都在 **盒子上的 Termux** 里运行（除标注外），路径默认
`/data/data/com.termux/files/home`（Termux 的 `$HOME`）。

## 安装/修复类

| 脚本 | 用法 | 作用 |
|---|---|---|
| `shims-32bit.py` | `~/ha-venv/bin/python shims-32bit.py` | **32 位盒子必备**：为 orjson / ulid-transform / fnv-hash-fast / uv 安装纯 Python 垫片，绕开 Rust 编译 |
| `patch-android-platform.py` | `~/ha-venv/bin/python patch-android-platform.py` | 放行 HA 的 Android 平台检查（否则拒绝启动） |
| `sitecustomize.py` | 复制到 `~/ha-venv/lib/python3.*/site-packages/sitecustomize.py` | 修复 Android 上 `pycares.getaddrinfo` 不可用导致的 `Could not contact DNS servers` |
| `patch-d9-programs.py` | `~/ha-venv/bin/python patch-d9-programs.py` | 给美的 D9 复式洗烘一体机增加**左右筒程序 select**与**启动/暂停按钮**（升级后需重打） |
| `patch-midea-d9-default.py` | `~/ha-venv/bin/python patch-midea-d9-default.py` | 修复 midea_ac_lan 的 D9（复式洗烘一体机）实体不显示的 bug（升级集成后需重打） |

## 运行/守护类

| 脚本 | 用法 | 作用 |
|---|---|---|
| `start-ha.sh` | `nohup sh start-ha.sh >/dev/null 2>&1 &` | 设置 Termux 环境变量并启动 HA（也用于 runit 的 run 文件） |
| `stability/runit-setup.sh` | `bash stability/runit-setup.sh` | 把 HA 做成 runit 服务：崩溃自动拉起、开机自启 |

## 备份/自检/回滚

| 脚本 | 用法 | 作用 |
|---|---|---|
| `stability/backup-ha.sh` | `sh stability/backup-ha.sh` | 打包 `~/.homeassistant` 到 `~/stability/backups` + `/sdcard/Download/ha-backups`，保留 4 份 |
| `stability/watchdog.sh` | `sh stability/watchdog.sh`（或 runit 服务） | 看门狗：8123 健康探测（3 次失败重启，30 分钟冷却）、内存 <120MB 重启、磁盘 <2GB 清理旧备份并告警 |
| `stability/backup-schedule.sh` | `sh stability/backup-schedule.sh`（或 runit 服务 `backup`） | 每周自动备份 + 每月恢复演练 |
| `stability/upgrade.sh` | `sh stability/upgrade.sh --preflight` 等 | 升级 Runbook：preflight / repatch / verify / upgrade / rollback |
| `stability/ha_notify.py` | `ha_notify.py "标题" "内容"` | 通知助手：巴法云微信推送（HA 挂了也能发）+ HA 常驻通知 / notify 实体 |
| `stability/selftest.sh` | `sh stability/selftest.sh` | 17 项健康检查（备份/网页/启动标记/日志轮转/包锁定/runit/磁盘/回滚脚本/看门狗/备份调度/恢复演练） |
| `stability/rollback.sh` | `sh stability/rollback.sh list` | 回退工具（默认 dry-run，加 `--yes` 执行）：恢复配置、退回 nohup、解除包锁定、移除日志轮转 |

## 小爱/巴法云工具

| 脚本 | 用法 | 作用 |
|---|---|---|
| `bemfa-cleanup.py` | `~/ha-venv/bin/python bemfa-cleanup.py [--dry-run]` | 按 HA 里配置的同步清单，自动删除巴法云里多余的旧设备（避免米家里出现一堆垃圾设备） |
| `ha-ws-probe.py` | `python ha-ws-probe.py list-entities 关键字` | 用 HA 的 refresh token 换 access token，脚本化查询/改名/设区域（无需点网页） |

## 使用顺序建议

1. `shims-32bit.py`（仅 32 位）
2. `patch-android-platform.py`
3. `sitecustomize.py`
4. `start-ha.sh` 启动
5. `stability/runit-setup.sh` 守护
6. `stability/backup-ha.sh` + `selftest.sh` 建立安全网
