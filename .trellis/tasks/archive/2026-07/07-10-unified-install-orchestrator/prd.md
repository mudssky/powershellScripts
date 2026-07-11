# 统一安装编排器与预设

## Goal

在保留现有平台叶子脚本和根安装入口兼容行为的前提下，把根 `install.ps1` 扩展为跨平台 Stage 1 编排器。用户可以显式选择 Core 或 Full，查看步骤、预览变更、运行单步、从失败位置继续，并获得稳定的文本或 JSON 汇总。

首期交付稳定步骤引擎与未来标准路径合同；macOS、Linux/WSL、Windows 的真实新编号叶子由对应平台任务接入。

## Background

- 当前根 `install.ps1` 无参数调用执行仓库工具准备：Windows PATH、bin shim、Bash/Node 构建、nbstripout、AutoHotkey 与 Unix shell 部署。
- 无参数行为已被 README、`docs/INSTALL.md`、pnpm scripts、AI 操作说明和 `tests/Install.Tests.ps1` 使用，不能静默改成完整装机。
- 旧 `-installApp` 单独调用平台应用安装入口；它与 Full 预设并不等价。
- macOS 规划已冻结统一编号语义；网络源任务已提供 Stage 1 source transaction、Auto restore 和 China rollback 合同。
- 平台新编号叶子尚未全部存在，因此本任务不能通过临时映射旧脚本伪造完整 Core 成功。

## Confirmed Contracts

- 平台 Stage 0 负责获得 Git、平台包管理器和 PowerShell 7；根 Stage 1 从 `03 sources` 开始。
- Stage 1 步骤为 `03 sources`、`04 shell`、`05 core-cli`、`06 fonts`、`07 profile-tools`、`08 full-apps`、`09 platform-automation`、`10 login-items`、`11 desktop-integration`、`99 verify`。
- Core 选择 `03`～`07` 与 `99`；Full 在 Core 上追加 `08`～`11`。
- 平台不支持的步骤为 `Skipped`；声明支持但入口文件缺失为 `Blocked`。
- 平台叶子负责业务逻辑；根编排器只负责选择、排序、参数透传、依赖、状态和汇总。

## Requirements

### CLI 与兼容

- `install.ps1` 无参数调用继续执行现有仓库工具准备行为。
- 只有显式传入 `-Preset Core|Full` 才进入新编排器；Full 不得成为隐式默认值。
- 旧 `-installApp` 在迁移期继续调用现有平台应用安装路径并输出弃用提示，不映射为 Full。
- 支持 `-ListSteps`、`-Step <id[]>`、`-FromStep <id>`、`-SkipStep <id[]>`、`-NetworkMode Direct|China|Auto`、`-OutputFormat Text|Json`、`-Unattended`、`-NonInteractive` 与 PowerShell `-WhatIf`。
- `-Step` 与 `-FromStep` 互斥；执行型选择参数必须搭配 Preset；非法组合在产生副作用前返回 2。

### 选择与重跑

- `-Step` 只执行显式指定步骤，不自动展开依赖，并提示依赖未在本次运行中验证。
- `-FromStep` 从指定步骤开始执行 Preset 中的后续步骤。
- `-SkipStep` 从选中集合中排除步骤；依赖被排除时，下游步骤按依赖规则标为 `Blocked`。
- 首期不持久化 run manifest，不提供自动 `-Resume`；失败汇总必须给出可直接复制的 `-Step` 与 `-FromStep` 重跑命令。

### 执行与失败传播

- 步骤按稳定编号顺序串行执行，不并发修改系统状态。
- 步骤失败标为 `Failed`；依赖失败或被跳过的步骤标为 `Blocked`；独立步骤继续执行。
- `verify` 尽可能运行可执行的检查子集，不因前序失败被整体跳过。
- 整体退出码：成功/预览为 0，存在 `Failed` 为 1，参数错误为 2，仅存在 `Blocked` 为 10。
- 所有叶子命令使用参数数组调用，不通过拼接字符串或 `Invoke-Expression` 执行。

### Source 生命周期

- `NetworkMode` 默认 Direct；根编排器把 mode 和 transaction ID 传给平台 `03` 入口。
- Auto transaction 必须在 `finally` 中 Restore；恢复失败使整体至少为 `Blocked`。
- China transaction 保持 active，并在最终汇总中包含 transaction ID 与 Restore 命令。
- source 失败必须阻断依赖网络的 CLI、字体和应用步骤，不得静默继续并误报成功。

### 输出与自动化

- Text 为默认人工输出，包含步骤状态、耗时、错误摘要和重跑命令。
- JSON 模式 stdout 只输出一个稳定 document；叶子 stdout/stderr 必须被捕获并写入步骤结果或转发到 stderr，不能污染 JSON。
- JSON 顶层至少包含 schema version、run ID、platform、preset、network mode、preview、status、exit code、started/finished time、step results 和 rollback。
- 步骤结果至少包含 ID、编号、status、exit code、duration、message、dependsOn、command 和 rerun command。
- Ansible 或后续自动化只能消费该入口或平台叶子，不复制步骤图。

### 预览与交互

- 根 `-WhatIf` 必须透传为 PowerShell 叶子的 `-WhatIf` 或 shell 叶子的 `--dry-run`，且不得创建 source transaction、安装软件或写用户配置。
- `-Unattended` 与 `-NonInteractive` 互斥；严格非交互模式中叶子不得等待隐藏输入，无法满足前置时返回 `Blocked`。

## Acceptance Criteria

- [x] 无参数和 `-installApp` 兼容行为有回归测试及迁移说明。
- [x] 同一注册表能为 macOS、Linux/WSL 和 Windows 解析一致的 Stage 1 步骤模型。
- [x] Core/Full、ListSteps、Step、FromStep、SkipStep 和非法组合有确定性测试。
- [x] 依赖失败传播、独立步骤继续、verify 子集执行和退出码优先级有测试。
- [x] Text/JSON 汇总稳定，JSON stdout 不混入叶子日志。
- [x] Direct/China/Auto 生命周期有测试，Auto 在成功、失败和异常路径均尝试 Restore。
- [x] 缺失真实叶子时返回 `Blocked`；fixture 叶子可完整跑通成功、失败、预览和重跑场景。
- [x] 现有 README、安装文档、脚本索引与工程规范同步新 CLI 和兼容边界。
- [x] `pnpm qa` 与 `pnpm test:pwsh:all` 通过。
- [x] 用户审阅并批准 `prd.md`、`design.md` 与 `implement.md` 后才进入 implementation。

## Out of Scope

- 安装 Git、平台包管理器或 PowerShell 7 的 Stage 0 实现。
- 实现或重写 macOS、Linux/WSL、Windows 的真实编号叶子。
- 改造 `Install-PackageManagerApps` 的标签选择和结构化逐项结果。
- 持久化装机 run manifest、自动 Resume 或跨重启 checkpoint。
- 安装 Nix、Home Manager、nix-darwin 或实现 Ansible playbook。
