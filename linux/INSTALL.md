# Linux 与 WSL 安装指南

Linux 新机流程分为 Stage 0 与 Stage 1。首期完整支持 Ubuntu/Debian、Ubuntu/Debian WSL 客体和 `x86_64/amd64`；Arch 与 ARM 只提供识别和明确的 Blocked 结果。

## 推荐入口

在已有仓库中执行：

```bash
bash linux/00quickstart.sh --preset Core --network-mode Direct
```

Stage 0 会依次准备最小 apt/Git、Linuxbrew 和 PowerShell 7，然后移交根 Stage 1：

```powershell
pwsh ./install.ps1 -Preset Core -NetworkMode Direct
```

远程模式默认使用 shallow clone，允许覆盖仓库地址与目标目录：

```bash
bash linux/00quickstart.sh \
  --repo-url https://github.com/mudssky/powershellScripts.git \
  --repo-dir "$HOME/powershellScripts" \
  --preset Full
```

已有完整开发 clone 不会被 pull、重建或转换为 shallow history。

## 网络模式

- `Direct`：允许使用官方 apt、GitHub 与 Homebrew 下载路径。
- `China`：Linuxbrew 和 Stage 1 source 使用持久事务；汇总会提供 Restore 命令。
- `Auto`：仅在官方源不可用时创建临时事务，根编排器在结束时恢复。

PowerShell 7/chsrc 可用前没有 Linux 原生 Stage 0 apt 恢复 adapter。China/Auto 遇到缺少 `ca-certificates`、curl、Git、build-essential 或 PowerShell 时会返回 Blocked，不会静默回退 Direct。可通过预装前置、覆盖 repo URL 或提供本地 deb 继续：

```bash
bash linux/00quickstart.sh \
  --network-mode China \
  --powershell-package /path/to/powershell_7.x.x-1.deb_amd64.deb
```

## Core 与 Full

Core 执行 `03`～`07` 与 `99`：

- 发行版、Linuxbrew 和语言生态 source
- bash/zsh 受管配置片段
- Linuxbrew Core CLI
- 字体环境判断
- PowerShell Profile、模块、Node/pnpm、仓库工具与 Docker
- 只读验证

Full 在 Core 上增加 `08` 的 `terminal-extras` 高级 CLI。Linux 首期不安装 GUI 应用，`09`～`11` 由注册表标记为 `Skipped`。

```powershell
pwsh ./install.ps1 -Preset Core -WhatIf
pwsh ./install.ps1 -Preset Full -NetworkMode Direct
pwsh ./install.ps1 -Preset Core -Step core-cli
pwsh ./install.ps1 -Preset Core -FromStep profile-tools
```

## 独立叶子

| 编号 | 入口 | 职责 |
|---|---|---|
| 00 | `linux/00quickstart.sh` | Stage 0、shallow clone 与 Stage 1 移交 |
| 01 | `linux/01installHomeBrew.sh` | Linuxbrew |
| 02 | `linux/02installPowerShell.sh` | amd64 PowerShell 7 |
| 03 | `linux/03configureSources.sh` | package source 事务 |
| 04 | `linux/04deployShellConfig.sh` | bash/zsh 配置 |
| 05 | `linux/05installCoreCli.ps1` | Core CLI |
| 06 | `linux/06installFonts.ps1` | Auto/Desktop/Server 字体策略 |
| 07 | `linux/07installProfileTools.ps1` | Profile、仓库工具、Docker 与 WSL 客体配置 |
| 08 | `linux/08installFullApps.ps1` | Full terminal extras |
| 99 | `linux/99verifyInstall.ps1` | 只读验证 |

所有写入叶子支持 `--dry-run` 或 `-WhatIf`。退出码为：成功/已满足/内部跳过 0、失败 1、参数错误 2、外部前置 Blocked 10。

`linux/03deployShellConfig.sh` 与 `linux/04installApps.ps1` 只保留弃用转发，不再拥有安装逻辑。

## 字体

普通服务器和 WSL 默认跳过字体。Windows Terminal 使用 Windows 宿主字体，不需要在 WSL 内重复安装。

WSLg、PDF、图片或浏览器渲染需要 Linux fontconfig 时，可显式执行桌面模式：

```powershell
pwsh linux/06installFonts.ps1 -Environment Desktop -WhatIf
pwsh linux/06installFonts.ps1 -Environment Desktop
```

## WSL 与 Docker

- `linux/wsl/wsl.conf` 只属于 WSL 发行版客体。
- `.wslconfig`、WSL 安装和 `wsl --shutdown` 属于 Windows 宿主流水线。
- `docker info` 已成功时复用现有 Docker Desktop 集成或客体 Engine，不重复安装。
- 缺少可用 Docker 时，07 使用发行版系统包安装客体 Engine。
- 首次安装客体 Engine 时，07 会把当前用户加入 `docker` 组并验证 daemon；随后返回 Blocked/10，要求原生 Linux 重新登录或 WSL 执行宿主重启后重跑。
- `/etc/wsl.conf` 变化时先备份并原子替换，07 返回 Blocked/10；此时在 Windows 执行 `wsl --shutdown` 后重跑。

流水线自身不会修改 Windows 用户目录或执行宿主重启。

## 验证

```powershell
pwsh linux/99verifyInstall.ps1 -Preset Core
pwsh linux/99verifyInstall.ps1 -Preset Full -OutputFormat Json
pwsh linux/99verifyInstall.ps1 -Preset Core -Step docker
```

JSON stdout 只有一个文档。验证是只读操作，状态优先级为 Failed/1、Blocked/10、Succeeded/0。

## FNOS 外接数据盘

FNOS 挂载管理是独立工具，不属于新机 Core/Full：

```bash
bash linux/fnos/fnos-mount-manager/build.sh
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh check
```

详细用法参见 `linux/fnos/fnos-mount-manager/README.md`。

跨平台 Stage 1 总说明：[docs/INSTALL.md](../docs/INSTALL.md)
