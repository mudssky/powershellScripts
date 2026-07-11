# macOS 安装流水线验证记录

验证日期：2026-07-11

## 自动化门禁

- `pnpm test:bash`：5 files、21 tests passed。
- `pnpm qa`：PowerShell QA 172 passed、0 failed、6 not run。
- `pnpm test:pwsh:all`：
  - macOS host：713 passed、0 failed、4 skipped、24 not run。
  - Linux Docker：709 passed、0 failed、8 skipped、24 not run。
- macOS Pester 窄测：`MacOSInstallPipeline.Tests.ps1` 15 tests passed。
- `zsh -n`、`bash -n`、PowerShell parser、`plutil -lint` 与 `git diff --check` 通过。

## 实机只读验证

### Core

命令：

```zsh
zsh macos/99verifyInstall.zsh --preset Core --output-format json
```

结果：32 passed、0 warned、3 failed、0 blocked，退出 1。

缺失项：

- `font-jetbrains-mono-nerd-font`
- 当前 `$PROFILE` 未指向仓库统一入口
- `bin/aliyun-oss-put` Bash 构建产物

### Full

命令：

```zsh
zsh macos/99verifyInstall.zsh --preset Full --output-format json
```

结果：37 passed、1 warned、17 failed、0 blocked，退出 1。

除 Core 缺失项外，当前机器尚未执行以下 Full 状态：

- GUI/platform：orbstack、hiddenbar、stats、iterm2、keka、maccy、mos、blueutil
- Hammerspoon：`config.lua`、`config.local.lua` 与托管 manifest
- 登录项：Hammerspoon、Mos
- Finder Quick Action

`jordanbaird-ice` 因 `skipInstall: true` 记录为 Warn，不改变退出码。

以上命令仅执行只读检查，没有安装软件、写入用户配置或启动 GUI。
