# Experience: WSL Ubuntu 22.04 → 24.04 原地升级

记录时间：2026-07-26  
环境：Windows 11 build 26200，WSL 2.5.10，发行版注册名 `Ubuntu-22.04`  
结果：成功，`VERSION_ID=24.04`（24.04.4 LTS noble），`do-release-upgrade exit=0`

## 实际流程

1. 先把当前 release 补到最新：`apt-get update && full-upgrade`
2. 设 `/etc/update-manager/release-upgrades` 的 `Prompt=lts`
3. `do-release-upgrade -c` 确认目标为 `24.04.4 LTS`
4. `do-release-upgrade -f DistUpgradeViewNonInteractive`（无交互确认）
5. 日志：`/var/log/dist-upgrade/{main,apt,history,apt-term}.log`

全程约 10–15 分钟量级（本机已有网络到 archive.ubuntu.com）；其中先做 jammy 全量更新会额外吃时间与流量（snapd 单包 ~34MB 等）。

## 遇到的问题（多数非致命）

### 1. 宿主脚本 NUL 解析（升级前踩到）

- 现象：`Initialize-WslHost.ps1` / `00quickstart.ps1` 调 `wsl --list --quiet` 后  
  `.Replace([char]0, '')` 在 pwsh 下抛：`Cannot convert value "" to type System.Char`
- 根因：`String.Replace(char, char)` 第二参数不能是空字符串；`wsl.exe` 输出常带 UTF-16 NUL
- 正确写法（仓库内已有先例 `ConvertFrom-WslSshText`）：

```powershell
(([string]$_) -replace [char]0, '').Trim()
```

- 修复位置：`windows/wsl/Initialize-WslHost.ps1`、`windows/00quickstart.ps1`

### 2. 升级器对 WSL 内核 uname 解析告警

```text
Kernel uname: '6.6.87.2-microsoft-standard-WSL2'
WARNING Can't parse kernel uname: 'too many values to unpack (expected 3)' (self compiled?)
```

- 影响：忽略即可；WSL 内核由 Windows 侧管理，发行版升级不换宿主内核
- 经验：不要因为这条 WARNING 中断；也不要在 WSL 内装/换 linux-image 元包（日志里也有 `linux metapackage () not available`）

### 3. polkitd 组解析失败（升级中）

```text
/usr/lib/tmpfiles.d/polkitd.conf: Failed to resolve group 'polkitd': No such process
```

- 常见于升级过程中用户/组尚未完全落定或服务未起
- 本机最终 `systemctl is-system-running=running`，可观察；若后续 polkit 异常再 `getent group polkitd` 排查

### 4. systemd-binfmt 被 mask

```text
Failed to restart systemd-binfmt.service: Unit systemd-binfmt.service is masked.
```

- WSL 环境常见，一般可忽略；不要强行 unmask 除非明确需要 binfmt 场景

### 5. “Please reboot” / dbus 替换

```text
A reboot is required to replace the running dbus-daemon.
Please reboot the system when convenient.
```

- **WSL 的 reboot = 宿主执行 `wsl --shutdown` 后重开发行版**，不是 Windows 整机重启（除非功能启用本身要求）
- 本会话宿主 `.wslconfig` 也是 RestartRequired；一次 shutdown 可同时覆盖配置与升级后服务重绑

### 6. 发行版注册名与内部版本脱节

- `wsl -l -v` 仍显示 `Ubuntu-22.04`，但 `/etc/os-release` 已是 noble 24.04
- 影响：
  - 脚本默认 `-Distribution Ubuntu-24.04` 会对不上现机
  - 心智负担：名字像 22.04，实际 24.04
- 选项：接受现状并在调用处显式传 `Ubuntu-22.04`；或另做 export/import 改名（等于迁移，非原地）

### 7. Docker Desktop 集成掉线

- 升级后 `docker` 报：当前 WSL distro 里找不到 docker，提示去 Desktop 开 WSL integration
- `docker-desktop` 发行版在升级过程中曾 Stopped
- 用户仍在 `docker` 组；不是组权限问题，是 **Desktop ↔ distro 集成/旁路 distro 状态**
- 恢复：Docker Desktop → Settings → Resources → WSL integration → 勾选该发行版；必要时先启动 Docker Desktop 再 `wsl -d Ubuntu-22.04`

### 8. 包生命周期噪声

- `Failed to find a replacement for python3.10` / `usrmerge`：预期（3.10 退役、usrmerge 在 24.04 已完成）
- `Obsolete` 列表含旧 `python3.10*`、部分过渡库；`powershell` 曾出现在 keep/obsolete 相关调试输出——若依赖 WSL 内 `pwsh`，升级后应再跑 `pwsh --version` / `apt policy powershell`
- snap 相关 unit “disabled or static, not starting”：WSL 上常见，非失败信号
- dpkg：`unable to delete old directory '.../reboot.target.wants': Directory not empty`：清理阶段噪声，通常无害

### 9. 非交互升级方式

- 有效：`DEBIAN_FRONTEND=noninteractive` + `do-release-upgrade -f DistUpgradeViewNonInteractive`
- 配合：`NEEDRESTART_MODE=a`、`Dpkg::Options --force-confdef/confold` 减少配置文件提问
- 风险：conffile 冲突默认 keep old，可能留下 jammy 残留配置；关键服务（sshd、docker、resolv）升级后应 diff 一下

### 10. 无 export 备份（本次用户选择）

- 成功则省时间；失败或半升级时 **没有** `wsl --import` 回滚点
- 经验：生产/不可重建环境仍建议先 `wsl --export`；可复现实验机可跳过

## 可复用检查清单

```bash
# 升级前
cat /etc/os-release
grep ^Prompt= /etc/update-manager/release-upgrades   # 应为 lts 或 normal
sudo apt-get update && sudo apt-get full-upgrade -y
do-release-upgrade -c

# 升级
sudo do-release-upgrade -f DistUpgradeViewNonInteractive
# 或交互：sudo do-release-upgrade

# 升级后（Windows）
wsl --shutdown
wsl -d Ubuntu-22.04 -- cat /etc/os-release
wsl -d Ubuntu-22.04 -- systemctl is-system-running
wsl -d Ubuntu-22.04 -- bash -lc 'pwsh --version; docker info; groups'
```

## 对仓库的启示

1. **NUL 清理统一用 `-replace [char]0, ''`**，禁止 `.Replace([char]0, '')`；长期可抽到 `WindowsInstall`/`WindowsBootstrap` 公共 helper，避免 00 与 WslHost 各写一份。
2. **发行版“显示名”≠ os-release 版本**；自动化应以 guest 内 `VERSION_ID` 为准，不要只信 `wsl -l` 名称。
3. **流水线默认 distro 名 `Ubuntu-24.04`** 与原地升级机常见名 `Ubuntu-22.04` 冲突——文档/参数应允许“名旧版新”。
4. Docker 验收不要只查 `docker` 组；要 `docker info`，并区分 Desktop 集成 vs 客体 Engine。
5. 任何 WSL 配置/大版本升级后的“重启”文案应写清：`wsl --shutdown`，避免用户去重启 Windows。
