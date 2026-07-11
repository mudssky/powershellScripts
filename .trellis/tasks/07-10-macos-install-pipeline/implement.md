# macOS 安装流水线实施计划

## 开始前依赖

- [x] `07-10-network-source-bootstrap` 已提供 macOS source adapter、Direct/China/Auto 参数和退出状态契约。
- [x] `07-10-unified-install-orchestrator` 已提供 Stage 1 调用接口、步骤注册格式和 Core/Full 参数。
- [x] 用户已审阅当前 `prd.md`、`audit.md`、`design.md` 与本实施计划，并明确批准开始。
- [x] 执行 `trellis-before-dev`，加载 psutils、shell、Hammerspoon、Quick Actions 相关规范。

## 1. 固化应用选择契约

- [x] 在 `psutils/modules/install.psm1` 中抽出纯应用选择函数，支持 OS、required tags、any tags、excluded tags 与 `skipInstall`。
- [x] 为应用标签增加校验函数：禁止 `core/full` 冲突，预设项必须且只能有一个类别，保留标签拼写必须有效。
- [x] 扩展 `Install-PackageManagerApps` 返回逐项结构化结果，并在 required item 失败时让调用方可靠判定步骤失败。
- [x] 保留 `ConfigPath`、`ConfigObject`、现有 predicate 参数和 ShouldProcess 行为。
- [x] 更新 `psutils.psd1` 导出清单以及函数帮助。
- [x] 在 `psutils/tests/install.Tests.ps1` 增加标签选择、skip 优先、WhatIf、部分失败继续与汇总失败测试。

验证：

```bash
pnpm --filter psutils test:qa
```

## 2. 标记 macOS 应用清单

- [x] 在 `profile/installer/apps-config.json` 为 10 个 Core CLI 增加 `core`、`cli`，保留现有场景标签。
- [x] 为 3 个 Nerd Fonts 增加 `core`、`font`。
- [x] 为当前 macbook GUI 增加 `full`、`gui`；为 blueutil 等平台依赖增加 `full`、`platform`。
- [x] 为可选终端工具增加 `cli`、`terminal-extras`，不增加 `core/full`。
- [x] 为 npm/bun AI CLI 增加 `ai-cli`、`cli`，不增加 `core/full`；不在本任务决定 npm/bun 唯一 provider。
- [x] 保持 `skipInstall: true` 条目跳过，并运行标签校验。

## 3. 重排 Stage 0 与基础步骤

- [x] 新增 `macos/00bootstrap.zsh`，实现本地/远程 resume、repo 参数和三种交互等级。
- [x] 将 `01installHomeBrew.sh` 重命名为 `01installHomebrew.zsh`，补严格模式、前检、help、dry-run、NONINTERACTIVE 和 shellenv。
- [x] 将 `02installPowerShell.sh` 重命名为 `02installPowerShell.zsh`，补 brew PATH、PowerShell 7 基线、Stage 0 helper 包装、dry-run 和验证。
- [x] 新增 `03configureSources.zsh`，只包装网络源 adapter。
- [x] 将 `03deployShellConfig.sh` 重命名为 `04deployShellConfig.zsh`，去除 chmod、透传参数、修正缺文件退出码。
- [x] 扩展 `shell/deploy.sh`：修改现有 rc 前备份、未变化不写、保持 Bash/Zsh 行为。

验证：

```bash
zsh -n macos/00bootstrap.zsh macos/01installHomebrew.zsh macos/02installPowerShell.zsh macos/03configureSources.zsh macos/04deployShellConfig.zsh
bash -n shell/deploy.sh
zsh macos/00bootstrap.zsh --help
zsh macos/01installHomebrew.zsh --dry-run
zsh macos/02installPowerShell.zsh --dry-run
zsh macos/03configureSources.zsh --dry-run --network-mode Direct
zsh macos/04deployShellConfig.zsh --dry-run
```

## 4. 新增 Core PowerShell 叶子步骤

- [x] 新增 `05installCoreCli.ps1`，通过共享 resolver 加载 JSON，选择 `macOS + core + cli` 并汇总结果。
- [x] 新增 `06installFonts.ps1`，选择 `macOS + core + font`，复用字体/包安装能力并支持 WhatIf。
- [x] 新增 `07installProfileTools.ps1`，按设计调用模块、Profile、fnm/Node/pnpm、bin、Bash/Node 构建和 nbstripout。
- [x] 修改 `profile/features/install.ps1`，仅在目标 Profile 内容变化时备份和写入，并支持 ShouldProcess。
- [x] 修改 `profile/installer/installModules.ps1`，按平台选择模块，macOS 不安装 BurntToast。
- [x] 清理 `Manage-BinScripts.ps1` 同一 shim 的重复写入，并确保失败可汇总。
- [x] 为应用选择、Profile 幂等、模块平台选择和 05～07 的 WhatIf/失败行为增加 Pester 测试。

窄验证：

```bash
pwsh -NoProfile -File macos/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -File macos/06installFonts.ps1 -WhatIf
pwsh -NoProfile -File macos/07installProfileTools.ps1 -WhatIf
```

## 5. 重排 Full 平台步骤

- [x] 将旧 `04installApps.ps1` 的 GUI 职责迁移到 `08installFullApps.ps1`；不再隐式安装字体。
- [x] 将 `05deployHammerspoon.sh` 重命名为 `09deployHammerspoon.zsh`，去除 wrapper chmod。
- [x] 优化 `macos/hammerspoon/load_scripts.zsh`，相同内容不备份、不复制，保持 manifest 与 local config。
- [x] 将 `07configureLoginItems.zsh` 重命名为 `10configureLoginItems.zsh`，dry-run 不解析真实 App，增加 remove/uninstall 与受控查找。
- [x] 将 `08installQuickActions.zsh` 重命名为 `11installQuickActions.zsh`，增加备份、临时目录配置、验证后替换和准确 manifest/文案。
- [x] 更新 Hammerspoon、Quick Actions 相关规范中的文件名和命令示例。

验证：

```bash
pwsh -NoProfile -File macos/08installFullApps.ps1 -WhatIf
zsh -n macos/09deployHammerspoon.zsh macos/hammerspoon/load_scripts.zsh macos/10configureLoginItems.zsh macos/11installQuickActions.zsh
zsh macos/09deployHammerspoon.zsh --dry-run --no-launch
zsh macos/10configureLoginItems.zsh --dry-run
zsh macos/11installQuickActions.zsh --dry-run
plutil -lint "macos/quick-actions/Fix App Open Issue.workflow/Contents/Info.plist"
plutil -lint "macos/quick-actions/Fix App Open Issue.workflow/Contents/document.wflow"
```

## 6. 重排与扩展验证入口

- [x] 将 `06verifyInstall.zsh` 重命名为 `99verifyInstall.zsh`。
- [x] 增加 source、Core CLI、fonts、modules、Profile、bin 和 repo tools 检查。
- [x] 增加 `--preset Core|Full`、保留 `--step`，并提供根编排器可消费的结构化输出。
- [x] 期望软件从 `apps-config.json` 动态读取；pwsh 缺失时按依赖跳过而不是维护硬编码名单。
- [x] 更新所有错误提示到新编号入口。
- [x] 增加 macOS Pester/命令测试，覆盖 help、参数错误、dry-run 不写入、preset 选择与结构化摘要。

## 7. 更新仓内引用与文档

- [x] 更新 `macos/INSTALL.md` 为新编号、Core/Full、网络模式和 unattended 模式。
- [x] 更新 `docs/INSTALL.md`、根 README、脚本注释、测试、规范和所有旧文件名引用。
- [x] 用 `rg` 确认不存在未解释的旧 `macos/01`～`08` 调用。
- [x] 记录仓外调用方不提供 shim 的迁移说明。

检查：

```bash
rg -n "macos/(01installHomeBrew|02installPowerShell|03deployShellConfig|04installApps|05deployHammerspoon|06verifyInstall|07configureLoginItems|08installQuickActions)" .
```

预期只允许历史归档或迁移说明命中；活动入口不得命中。

## 8. 最终质量门禁

- [x] 运行全部静态语法和 dry-run 检查。
- [x] 运行根 PowerShell 全量测试。
- [x] 运行根 QA 并修复问题。
- [x] 在 macOS 上分别执行 `99 --preset Core` 与可执行的 Full 子集，记录当前机器缺失项；验证脚本保持只读。
- [x] 确认工作树没有自动生成的本机配置、备份或安装产物被纳入提交。

```bash
pnpm test:pwsh:all
pnpm qa
```

## 风险与回滚点

- `apps-config.json` 标签迁移：先完成选择函数测试，再批量加标签；发现漏装时回退标签即可，不回退安装函数契约。
- 文件重命名：使用 Git rename 并在同一批次更新引用；提交前用 `rg` 检查。
- Profile/shell 用户文件：只在内容变化时生成时间戳 `.bak`；测试使用临时 HOME/PROFILE，不直接覆盖真实配置。
- Homebrew/字体/GUI 安装：开发验证默认使用 dry-run/WhatIf，真实安装需单独明确执行。
- Quick Actions/Hammerspoon：验证使用临时目录或 dry-run；真实用户目录写入前保留备份和 uninstall 路径。
- source adapter 与根编排器接口不匹配时停止实施并回到对应子任务修订契约，不在 macOS wrapper 中加兼容分支堆叠。
