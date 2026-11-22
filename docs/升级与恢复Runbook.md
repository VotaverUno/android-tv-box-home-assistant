# 升级与恢复 Runbook

> 适用于这台盒子（32 位 armv7 + Termux + HA Core venv）。
> 所有命令在盒子 Termux 里执行。**升级前必须先跑 preflight（会自动备份）。**

---

## 0. 三个脚本

| 脚本 | 作用 |
|---|---|
| `~/stability/scripts/backup-schedule.sh` | 每周自动备份 + 每月恢复演练（runit 服务 `backup`） |
| `~/stability/scripts/upgrade.sh` | 升级 Runbook：preflight / repatch / verify / upgrade / rollback |
| `~/stability/scripts/selftest.sh` | 17 项健康自检 |

---

## 1. 备份定时化（已上线）

### 行为
- runit 服务 `backup` 常驻，每小时检查一次；
- **每周**（≥7 天）自动执行 `backup-ha.sh`，保留最新 4 份；
- **每月**（≥30 天）自动做一次**恢复演练**：
  1. 取最新备份解压到临时目录；
  2. 校验 `configuration.yaml` 存在且含 `homeassistant:`；
  3. 校验 `.storage/core.config_entries` 是合法 JSON；
  4. 校验 `custom_components` 数量 ≥1；
  5. 结果写入 `~/stability/backup-schedule/drill-result`，失败会推送告警。

### 常用命令
```bash
# 手动触发（不影响正式数据）
bash ~/stability/scripts/backup-schedule.sh --force-backup
bash ~/stability/scripts/backup-schedule.sh --force-drill

# 状态
bash ~/stability/scripts/backup-schedule.sh --status
sv status backup
cat ~/stability/backup-schedule/drill-result
tail -n 20 ~/stability/logs/backup-schedule.log
```

---

## 2. 升级 Runbook

### 2.1 升级前：preflight（必做）

```bash
bash ~/stability/scripts/upgrade.sh --preflight
```

会做：
1. 新建快照目录 `~/stability/upgrades/<时间戳>/`；
2. 记录当前 **HA 版本 / Python 版本 / pip freeze**；
3. 备份**补丁文件**（sitecustomize、fix_ha_android.py、patch_d9.py、patch_mobile_app.sh、shims32.py、midea_devices.py、mobile_app manifest）；
4. 全量备份配置（tar，路径写入快照目录的 `backup.txt`）。

### 2.2 升级 + 重打补丁 + 验证（推荐一条命令）

```bash
# 升级到最新版（失败可加 --yes 自动回滚）
bash ~/stability/scripts/upgrade.sh --all --yes

# 或指定版本
bash ~/stability/scripts/upgrade.sh --all 2026.12.0 --yes
```

流程：`preflight → repatch → pip install → restart → verify`。

**verify 三项**：
1. `selftest.sh` 17 项全 PASS；
2. `hass --script check_config` 通过；
3. 等待 `:8123` 恢复（最多 3 分钟）。

### 2.3 分步执行（想手动控制时）

```bash
bash ~/stability/scripts/upgrade.sh --preflight     # 备份+快照
bash ~/stability/scripts/upgrade.sh --repatch       # 只重打补丁
bash ~/stability/scripts/upgrade.sh --upgrade       # 只升级（不指定=最新）
bash ~/stability/scripts/upgrade.sh --verify        # 只验证
```

### 2.4 升级失败：回滚

```bash
# 先干跑看看会做什么
bash ~/stability/scripts/upgrade.sh --rollback --dry-run

# 真正回滚（恢复配置 + 装回旧版本 + 重打补丁 + 验证）
bash ~/stability/scripts/upgrade.sh --rollback
```

回滚依据：最近一次 preflight 快照目录里的
`pip-homeassistant.txt`（旧版本号）和 `backup.txt`（配置备份路径）。

### 2.5 必须检查的补丁（升级后会被覆盖）

| 补丁 | 失效表现 | 重打方式 |
|---|---|---|
| Android 平台放行 | HA 直接退出：`Home Assistant only supports Linux...` | `--repatch`（自动） |
| sitecustomize DNS | 云登录失败：`Could not contact DNS servers` | `--repatch`（自动） |
| 32 位垫片 | 启动报 JSON 错误或 import 失败 | `--repatch`（自动检查，缺则重装） |
| mobile_app manifest | 手机 App 连不上（404） | `--repatch`（自动） |
| 美的 D9 默认实体 | D9 洗衣机 0 实体 | `--repatch`（自动） |

> `--repatch` 已全部自动化；跑完仍建议手动确认日志：`grep -iE "error|xception" ~/ha.log | tail`。

---

## 3. 升级日志与核对

```bash
tail -n 60 ~/stability/logs/upgrade.log
ls -1t ~/stability/upgrades/ | head -3
cat ~/stability/upgrades/last
```

升级成功后建议：
1. 重启手机 App 确认连接；
2. 抽查美的/海尔设备状态是否正常；
3. 小爱语音抽测一条；
4. 把本次升级记录补到 `CHANGELOG`（仓库侧）。

---

## 4. 常见问题

| 问题 | 处理 |
|---|---|
| 升级后 HA 起不来 | `--rollback`（用最近快照） |
| 升级后实体大量 unavailable | 先看 `ha.log`；多半是补丁丢失 → `--repatch` |
| pip 安装卡住 | 检查 `~/pip.conf` 镜像是否可用；重试 `--upgrade` |
| 空间不足 | `df -h /data`；清理旧备份（脚本自动保留 4 份） |
| 想固定版本避免自动升级 | 不要跑 `--upgrade`；apt/pip 均不会自动升级 |
