# macOS 安装流水线规范

## Scenario: macOS Stage 0、Core/Full 叶子与只读验证

### 1. Scope / Trigger

- Trigger: 修改 `macos/00bootstrap.zsh`、编号 `01`～`11` 叶子、`macos/99verifyInstall.zsh`、`macos/pwsh/Test-InstallState.ps1`、macOS 应用标签或根编排器中的 macOS 路径。
- Scope: macOS Stage 0、Stage 1 叶子参数、Core/Full 软件选择、桌面集成幂等和平台验证。
- Design intent: 根编排器拥有步骤图，macOS 叶子只拥有平台业务；软件安装和验证共享 `apps-config.json`，不复制包名。

### 2. Signatures

```zsh
zsh macos/00bootstrap.zsh \
  [--repo-url <url>] [--repo-dir <path>] \
  [--preset Core|Full] [--network-mode Direct|China|Auto] \
  [--unattended|--non-interactive] [--dry-run]

zsh macos/04deployShellConfig.zsh --preset Core|Full [--dry-run]
zsh macos/09deployHammerspoon.zsh --preset Full [--dry-run] [--no-launch] [--install]
zsh macos/10configureLoginItems.zsh --preset Full [--dry-run] [--remove|--uninstall]
zsh macos/11installQuickActions.zsh --preset Full [--dry-run] [--uninstall]
zsh macos/99verifyInstall.zsh [--preset Core|Full] [--step <id>] [--output-format text|json]
```

```powershell
pwsh macos/05installCoreCli.ps1 -Preset Core|Full [-WhatIf]
pwsh macos/06installFonts.ps1 -Preset Core|Full [-WhatIf]
pwsh macos/07installProfileTools.ps1 -Preset Core|Full [-WhatIf]
pwsh macos/08installFullApps.ps1 -Preset Full [-WhatIf]
pwsh macos/pwsh/Test-InstallState.ps1 `
  -Step core-cli|fonts|full-apps|profile-tools `
  -OutputFormat Tsv|Json
```

### 3. Contracts

- 物理编号固定为 `00 bootstrap`、`01 package-manager`、`02 pwsh`、`03 sources`、`04 shell`、`05 core-cli`、`06 fonts`、`07 profile-tools`、`08 full-apps`、`09 platform-automation`、`10 login-items`、`11 desktop-integration`、`99 verify`。
- `00` 远程获取仓库时使用 `git clone --depth=1`；获得 PowerShell 7 后必须移交根 `install.ps1 -Preset`，不得保存第二份步骤图。
- Core 选择 `03`～`07` 与 `99`；Full 在 Core 上追加 `08`～`11`。所有非 source zsh 叶子必须接受根编排器透传的 `--preset` 和交互模式参数。
- `apps-config.json` 是软件真源：`05 = core + cli`，`06 = core + font`，`08 = full + (gui OR platform)`；`skipInstall: true` 始终优先。
- zsh 预览使用 `--dry-run`，PowerShell 预览使用 `-WhatIf`；预览不得安装、写用户配置、启动 GUI，且不得因 fnm、uv 或目标 App 尚未安装而阻塞计划生成。
- 退出码固定为 0 成功/已满足/预览，1 执行或验证失败，2 参数错误，10 外部权限或前置 Blocked。
- Hammerspoon 相同内容不备份、不复制；Quick Action 先在 Services 同文件系统临时目录配置和 `plutil` 校验，变化时备份后原子替换；登录项 dry-run 不调用 AppleScript。
- `99` 只读；Core/Full 默认步骤按预设选择，`--step` 精准检查。JSON stdout 只能有一个 document，字段至少包含 `Preset`、`Status`、`ExitCode`、`Counts`、`Results`。
- `Test-InstallState.ps1` 通过共享选择器和安装检测读取应用期望；pwsh 缺失时 `99` 报告依赖检查 Blocked，不维护硬编码替代名单。
- macOS 默认 Bash 3.2 + `set -u` 下，空数组展开和裸 `return` 可能产生非零状态；空列表必须用显式计数守卫，跳过分支必须 `return 0`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| `--unattended` 与 `--non-interactive` 同时使用 | 参数错误，退出 2 |
| 根编排器向 04/09/10/11 传入合法 `--preset` | 叶子接受并继续，不把公共参数转交底层业务脚本 |
| `02 --dry-run` 且 Homebrew 尚未安装 | 使用架构默认 brew 路径生成计划，不返回 Blocked |
| 应用清单存在未知标签、core/full 冲突或多类别 | 校验失败，安装叶子退出 1 |
| Hammerspoon 源和目标相同 | 不创建 `.bak`，不复制，manifest 相同也不重写 |
| 登录项 dry-run | 不调用 `osascript`，只打印声明项 |
| Quick Action 目标变化 | 创建可读时间戳 `.bak`，临时目标验证后原子替换 |
| `99 --output-format json` | stdout 可被 `ConvertFrom-Json` 直接解析为一个 document |
| 只读系统权限不足 | 对应项为 Blocked；没有 Fail 时整体退出 10 |
| Bash 3.2 空 exclude 列表 | shell dry-run 正常完成，不出现 unbound variable |

### 5. Good / Base / Bad Cases

- Good: 根 `install.ps1 -Preset Full -WhatIf` 中 03～11 都为 Preview，99 独立报告当前真实安装状态。
- Good: 修改 `apps-config.json` 标签后，05/06/08 和 99 同时得到新选择结果。
- Base: 手工单跑 10/11 时使用 Full preset；缺少 TCC/Automation 权限返回 Blocked。
- Bad: 在 99 中再写一份 Core CLI 或 Full GUI 包名数组。
- Bad: wrapper 通过 `chmod` 修改仓库文件，或把 `--preset` 原样传给不认识该参数的底层 loader。
- Bad: 使用 `rm -rf target && copy` 覆盖 workflow，留下无备份或半成品窗口。

### 6. Tests Required

- Pester：05/06/08 标签边界、07 无外部工具 WhatIf、模块平台矩阵、Profile 只在变化时备份。
- Pester/macOS：04 空 exclude dry-run、09 重跑零备份、10 dry-run 零 AppleScript、11 临时 HOME 原子替换和备份。
- Pester：99 参数错误、单文档 JSON、`--step`、应用名称来自 `apps-config.json`。
- Shell：所有编号 zsh `zsh -n`，`shell/deploy.sh` `bash -n`，Quick Action plist `plutil -lint`。
- Integration：`install.ps1 -Preset Full -WhatIf -OutputFormat Json` 中 03～11 不得出现参数错误。
- Gates：`pnpm test:bash`、`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```bash
for pattern in "${EXCLUDE_LIST[@]}"; do
  ...
done

[ -f "$optional_rc" ] || return
```

在 macOS Bash 3.2 的 `set -u` 下，空数组可能报未绑定；裸 `return` 还会继承上一条失败条件的状态并触发 `set -e`。

#### Correct

```bash
if [ "$EXCLUDE_COUNT" -gt 0 ]; then
  for pattern in "${EXCLUDE_LIST[@]}"; do
    ...
  done
fi

[ -f "$optional_rc" ] || return 0
```

理由：显式区分“没有工作”和“执行失败”，Core/Full 编排器才能稳定解释叶子退出码。
