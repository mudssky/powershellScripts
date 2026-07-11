# Linux WSL 安装流水线实施计划

## 开始门禁

- [x] 用户审阅 `prd.md`、`audit.md`、`design.md` 与本计划，并明确批准实现。
- [x] 执行 `task.py start 07-10-linux-wsl-install-pipeline`，确认任务状态为 `in_progress`。
- [x] 加载 `trellis-before-dev`，阅读 infra、bash、pwsh、profile、psutils 与 shell-shared 相关规范。
- [x] 开始前记录 `git status --short`，只处理本任务文件，不吸收其他未跟踪任务目录。

## 1. 平台模型与系统包清单

- [x] 新增 `config/install/linux-packages.psd1`，声明 schema、Ubuntu/Debian 系统工具、Docker 候选包和桌面字体包。
- [x] 新增 `linux/pwsh/LinuxInstall.psm1`，实现发行版、WSL、systemd、桌面和架构探测。
- [x] 为平台模型提供 os-release/proc/uname/环境覆盖注入，仅供 fixture 测试使用。
- [x] 实现统一组件结果、退出优先级；所有函数补齐中文功能、参数和返回值帮助。原生命令包装在实际消费步骤中补齐。
- [x] 在 Pester 中覆盖 Ubuntu、Debian、WSL、Arch、arm64、unknown distro 与 systemd 状态。

验证：

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/LinuxInstallPipeline.Tests.ps1 -Tag Unit -Output Detailed"
```

## 2. Stage 0

- [x] 新增 `linux/lib/install-common.sh`，收口 Bash 日志、参数校验、平台识别和 sudo 预检。
- [x] 重写 `linux/00quickstart.sh`，支持 repo/preset/network/interactivity/local deb/dry-run 参数。
- [x] Direct 模式以最小 apt 前置获得 Git，并使用 `git clone --depth=1`；已有仓库只复用。
- [x] 重写 `linux/01installHomeBrew.sh`，恢复固定 Linuxbrew prefix，通过 POSIX helper 安装并验证，不写 rc。
- [x] 将 package source catalog 的 brew target 扩展到 Linux，并补 adapter 平台测试。
- [x] 重写 `linux/02installPowerShell.sh`，支持已安装版本、本地 deb、amd64 官方安装和 Blocked 路径。
- [x] 确保 Stage 0 dry-run 零写入，China/Auto 前置不足返回 10，成功后按参数数组移交根 `install.ps1`。
- [x] 在 Vitest 中用临时目录和 fake apt/git/curl/dpkg/pwsh 验证命令顺序、shallow clone、退出码和无隐式 Direct fallback。

验证：

```bash
pnpm vitest run --config ./scripts/bash/vitest.config.ts scripts/bash/tests/linux-install-pipeline.test.ts
bash -n linux/00quickstart.sh linux/01installHomeBrew.sh linux/02installPowerShell.sh linux/lib/install-common.sh
```

## 3. Sources 与 Shell

- [x] 新增 `linux/03configureSources.sh`，按发行版选择 system target，并组合 brew/npm/pnpm/pip/go。
- [x] 保证 JSON stdout 单文档，Direct/China/Auto 与事务 ID 原样委托共享引擎。
- [x] 新增 `shell/shared.d/homebrew.sh`，只加载已知 prefix 的 shellenv。
- [x] 新增 `linux/04deployShellConfig.sh`，仅适配根公共参数并调用 `shell/deploy.sh`。
- [x] 将 `linux/03deployShellConfig.sh` 收敛为弃用薄包装，不修改执行位。
- [x] 测试临时 HOME 下 bash/zsh loader、dry-run、未知参数、source target 选择和 JSON 隔离。

验证：

```bash
pnpm test:bash
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/LinuxInstallPipeline.Tests.ps1 -Tag Sources,Shell -Output Detailed"
```

## 4. Core 与 Full CLI

- [x] 新增 `linux/05installCoreCli.ps1`，复用 catalog validator 与 `Linux + core + cli` 选择。
- [x] 新增 `linux/08installFullApps.ps1`，只选择 `Linux + cli + terminal-extras`。
- [x] 两个叶子恢复 Linuxbrew PATH、支持 WhatIf、逐项汇总并正确映射 Failed/Blocked。
- [x] 检查 `apps-config.json` 中系统包与 Linuxbrew 条目没有重复所有权；只补必要标签，不新建 Linux GUI 项。
- [x] 将 `linux/04installApps.ps1` 改为弃用薄包装，并调整 `install.ps1 -installApp` Linux 分支指向新 Core CLI。
- [x] 扩展 Pester 覆盖 Core/Full 标签边界、skipInstall、空清单、部分失败继续和 macOS cask 隔离。

## 5. 字体

- [x] 新增 `linux/06installFonts.ps1 -Environment Auto|Desktop|Server`。
- [x] WSL、无桌面和识别不确定默认返回内部 NotApplicable，且不调用 apt/fc-cache。
- [x] Desktop 从系统包 catalog 生成 apt 计划，安装后更新并验证字体缓存。
- [x] WhatIf 与测试路径不访问真实系统字体目录或 apt。
- [x] 覆盖 WSL、server、desktop、显式覆盖、缺少 fontconfig 和包失败。

## 6. 共享 Profile Tools、Docker 与 WSL 客体配置

- [x] 从 `macos/07installProfileTools.ps1` 抽取 `scripts/pwsh/install/ProfileTools.psm1`，保持 macOS 行为不变。
- [x] macOS 07 改为共享模块薄包装，并先运行现有 macOS 窄测防止回归。
- [x] 新增 Linux 07，调用共享 Profile Tools 并追加 Linux 系统工具、Docker 与 WSL 组件。
- [x] 将客体模板移动到 `linux/wsl/wsl.conf`，实现内容比较、时间戳备份、临时文件验证和原子替换。
- [x] Docker 先执行可用性探测；已有 Docker Desktop/Engine 时跳过，缺失时按系统包 catalog 安装客体 Engine 与 Compose。
- [x] WSL config 变化时返回 RestartRequired/Blocked 10，不调用 `wsl.exe`；原生 Linux 验证 systemd service 与 `docker info`。
- [x] 使用 fixture target、fake sudo/systemctl/docker 测试全部写入和重启路径。

验证：

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/MacOSInstallPipeline.Tests.ps1,./tests/LinuxInstallPipeline.Tests.ps1 -Output Detailed"
```

## 7. 只读验证

- [x] 新增 `linux/pwsh/Test-InstallState.ps1`，从两个 catalog 读取期望状态。
- [x] 新增 `linux/99verifyInstall.ps1`，支持 Preset、Step 与 Text/Json。
- [x] 验证平台、架构、repo、brew、pwsh、sources、shell、CLI、Profile/tools、Docker 与 WSL config。
- [x] JSON stdout 保持单文档；Arch/ARM 报 Blocked，NotApplicable 不转为 Failed。
- [x] 测试 Core/Full、单步、未知步骤、单文档 JSON、catalog 名称来源和严格只读。

## 8. 文档与兼容

- [x] 更新 `linux/INSTALL.md`，只推荐 Stage 0 与根 Stage 1，不再串联旧 Ubuntu/Arch/WSL installer。
- [x] 更新 `docs/scripts-index.md` 与相关平台调用说明，明确 WSL guest/host、Docker 和字体边界。
- [x] 搜索并更新仓内对旧 Linux 03/04 和 `linux/wsl2/wsl.conf` 的有效引用。
- [x] 不移动 `linux/ubuntu/**`、`linux/archlinux/**`、`.wslconfig` 或其他归档候选；只记录新入口替代关系。

## 9. 质量门禁

- [x] PowerShell parser、`bash -n`、JSON/psd1 加载和 `git diff --check` 通过。
- [x] Linux Pester 窄测通过，且测试未修改真实 HOME、source、Docker 或 `/etc`。
- [x] `pnpm test:bash` 通过。
- [x] `pnpm qa` 通过。
- [x] `pnpm test:pwsh:all` 通过；记录 macOS host 与 Linux Docker 结果。
- [x] `install.ps1 -Preset Core|Full -WhatIf -OutputFormat Json` 在 Linux fixture/integration 中无参数错误。

最终验证：

```bash
pnpm test:bash
pnpm qa
pnpm test:pwsh:all
git diff --check
```

## 10. 收尾

- [x] 使用 `trellis-check` 完成规范、复用、跨层数据流和测试审查。
- [x] 新增 `.trellis/spec/infra/linux-install-pipeline.md`，记录稳定平台合同、错误矩阵与测试要求。
- [x] 按逻辑边界提交实现与文档；不提交其他未跟踪任务目录。
- [x] 记录最终验证结果。
- [x] 归档当前任务并更新 journal。

## 最终验证记录

- `pnpm test:bash`：6 files、30 tests 全部通过。
- `pnpm qa`：195 passed、2 skipped、6 not run；Linux 与 macOS 安装流水线均进入 changed QA 路由。
- `pnpm test:pwsh:all`：macOS host 736 passed、6 skipped、24 not run；Linux Docker 734 passed、8 skipped、24 not run。
- Linux 流水线窄测：macOS host 23 passed、2 个 Linux-only integration skipped；Linux Docker 25/25，通过 source 单文档 JSON 与根 Core WhatIf 参数链。
- PowerShell parser、显式 `pwshfmt-rs -Strict`、`bash -n`、JSON/PSD1 加载和 `git diff --check` 全部通过。
- 质量审查额外修复：Stage 0 完整 apt 前置识别、严格非交互 sudo 提示泄漏、Docker 组权限刷新与 Linux Pester QA 发现性。

## 风险与回滚点

- `ProfileTools.psm1` 抽取会影响已完成的 macOS 07，必须在 Linux 后续工作前先用 macOS Pester 锁定行为。
- `brew.platforms` 扩展会触及共享 source catalog，必须验证 macOS 现有 managed-env 路径没有改变。
- WSL config 是唯一系统配置写入；内容漂移、sudo 不足或重启未完成均返回 Blocked，不覆盖用户后续修改。
- Docker 安装只在 `docker info` 不可用且平台受支持时发生，不卸载或替换已有 Docker Desktop 集成。
- 任何真实 source Apply、apt 安装或 WSL 重启只由用户显式运行生产入口触发，默认测试与验收使用 WhatIf/fixture。
