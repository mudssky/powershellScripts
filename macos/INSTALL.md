# macOS 安装指南

macOS 流水线分为 Stage 0 与 Stage 1。默认预设为 Core；Full 必须显式选择。所有命令默认在仓库根目录执行。

## 推荐入口

已有仓库时直接运行：

```zsh
# 默认 Direct + Core
zsh macos/00bootstrap.zsh

# 预览完整 Full 流程
zsh macos/00bootstrap.zsh --preset Full --dry-run

# 一次 sudo 认证后无人值守执行 Core
zsh macos/00bootstrap.zsh --unattended
```

远程最小入口会使用 `git clone --depth=1`，可覆盖仓库地址和目录：

```zsh
zsh 00bootstrap.zsh \
  --repo-url https://github.com/mudssky/powershellScripts.git \
  --repo-dir "$HOME/powershellScripts"
```

`--non-interactive` 是严格零提示模式，只适用于已预置 sudo、CLT 和系统权限的 MDM/CI 环境。前置不足返回 10，不会等待隐藏输入。

## 预设

| 预设 | 步骤 |
|---|---|
| Core | `01` Homebrew、`02` PowerShell、`03` sources、`04` shell、`05` Core CLI、`06` fonts、`07` Profile/tools、`99` verify |
| Full | Core 加 `08` GUI/platform apps、`09` Hammerspoon、`10` login items、`11` Finder Quick Actions |

软件名称只来自 `profile/installer/apps-config.json`。Core CLI 使用 `core + cli`，字体使用 `core + font`，Full 应用使用 `full + gui/platform`；`skipInstall: true` 始终优先。

## 网络模式

- `Direct`：默认，不探测、不修改现有 source。
- `China`：创建持久事务，直到显式 Restore。
- `Auto`：仅在官方源连续失败时临时切换，根编排器在结束时恢复。

```zsh
zsh macos/00bootstrap.zsh --network-mode Direct
zsh macos/00bootstrap.zsh --network-mode China
zsh macos/00bootstrap.zsh --network-mode Auto
```

镜像 URL、状态和恢复由统一 source 引擎管理，macOS 叶子脚本不直接写 shell rc。

## Stage 1

Homebrew 和 PowerShell 7 已就绪时，可以直接进入根编排器：

```powershell
pwsh ./install.ps1 -Preset Core -NetworkMode Direct
pwsh ./install.ps1 -Preset Full -NetworkMode Direct
pwsh ./install.ps1 -Preset Core -WhatIf
pwsh ./install.ps1 -Preset Core -Step core-cli
pwsh ./install.ps1 -Preset Full -FromStep full-apps
```

## 独立叶子

每个步骤都可单独重跑。zsh 变更脚本支持 `--dry-run`，PowerShell 变更脚本支持 `-WhatIf`。

旧 `01`～`08` 文件名已一次性迁移，不保留兼容 shim。仓外脚本应改用下列新入口或根 `install.ps1 -Preset`。

```zsh
zsh macos/01installHomebrew.zsh --dry-run
zsh macos/02installPowerShell.zsh --dry-run
zsh macos/03configureSources.zsh --network-mode Direct --dry-run
zsh macos/04deployShellConfig.zsh --dry-run
pwsh macos/05installCoreCli.ps1 -WhatIf
pwsh macos/06installFonts.ps1 -WhatIf
pwsh macos/07installProfileTools.ps1 -WhatIf
pwsh macos/08installFullApps.ps1 -WhatIf
zsh macos/09deployHammerspoon.zsh --dry-run --no-launch
zsh macos/10configureLoginItems.zsh --dry-run
zsh macos/11installQuickActions.zsh --dry-run
```

回滚入口：

```zsh
zsh macos/10configureLoginItems.zsh --remove
zsh macos/11installQuickActions.zsh --uninstall
```

Hammerspoon 和 Quick Actions 只在内容变化时覆盖；覆盖前生成可读时间戳 `.bak`。登录项与桌面自动化仍受 macOS TCC/Automation 权限约束。

## 验证

`99verifyInstall.zsh` 只读，不安装包、不写用户配置、不启动 GUI。缺少必需项返回 1；权限或外部前置无法验证且没有失败时返回 10；WARN 不改变退出码。

```zsh
zsh macos/99verifyInstall.zsh --preset Core
zsh macos/99verifyInstall.zsh --preset Full
zsh macos/99verifyInstall.zsh --preset Core --step core-cli
zsh macos/99verifyInstall.zsh --preset Full --output-format json
```

应用和字体期望值由验证 helper 从 `apps-config.json` 动态读取，不维护第二份包名列表。

PowerShell 已就绪后，完整的跨平台编排参数见 [docs/INSTALL.md](../docs/INSTALL.md)。
