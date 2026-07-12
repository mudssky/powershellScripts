---
title: feat: add reusable interactive selection module
type: feat
status: completed
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-interactive-selection-module-brainstorm.md
---

# feat: add reusable interactive selection module

## Overview

为 `psutils` 新增一个专用的交互选择模块，统一承载“优先使用 `fzf`，缺失时自动降级到文本编号选择”的能力，并首先接入 benchmark 调度脚本。该计划直接承接 brainstorm 中已经确认的边界：模块放在 `psutils/modules/`，支持字符串与对象输入，默认单选、可切多选，返回原始项本身，对象显示逻辑必须由调用方显式指定（see brainstorm: `docs/brainstorms/2026-03-14-interactive-selection-module-brainstorm.md`）。

这次改动的目标不是只改善 `Invoke-Benchmark.ps1` 的单点体验，而是沉淀出一个可被多个脚本复用的交互选择基础设施，避免在 benchmark、清理脚本或未来工具中重复处理 `fzf` 检测、文本降级和多选解析。

## Problem Statement / Motivation

当前 benchmark 调度脚本在缺少 `Name` 参数时直接报错，只让用户手动跑 `--list`（`scripts/pwsh/devops/Invoke-Benchmark.ps1:88`）。这个行为虽然能工作，但交互体验明显弱于仓库中已有的一些命令行工具模式，尤其是不符合“脚本自己引导用户完成选择”的目标。

仓库里已经存在两类相关实现，但都没有沉成公共能力：

- `psutils/modules/functions.psm1` 中已有 `Invoke-FzfHistorySmart` 和 `Register-FzfHistorySmartKeyBinding`，说明 `fzf` 交互本身已经被视为可复用的 CLI 体验能力（`psutils/modules/functions.psm1:119`, `psutils/modules/functions.psm1:251`）。
- `scripts/pwsh/devops/Clean-DockerImages.ps1` 里又单独实现了 `Get-FzfInstallHint`、`Assert-FzfAvailable`、`Select-CandidatesByFzf`，说明脚本级复用需求已经出现，但目前逻辑仍分散（`scripts/pwsh/devops/Clean-DockerImages.ps1:208`, `scripts/pwsh/devops/Clean-DockerImages.ps1:224`, `scripts/pwsh/devops/Clean-DockerImages.ps1:230`）。

如果现在只在 benchmark 脚本里继续加局部 `fzf` 逻辑，下一次遇到类似的候选项选择场景时还会继续复制这一套。更合理的方向是把交互选择统一下沉到 `psutils`，让调用方只负责提供候选项和显示逻辑。

## Proposed Solution

### 1. 新增专用 `selection.psm1` 模块

在 `psutils/modules/` 下新增一个专用模块，例如 `selection.psm1`，用于承载交互选择能力，而不是继续把逻辑塞进 `functions.psm1`。该模块加入 `psutils/psutils.psd1` 的 `NestedModules` 和 `FunctionsToExport`，成为标准可导出的公共 API。

选择专用模块而不是复用 `functions.psm1` 的原因是职责隔离：历史搜索、PSReadLine 快捷键绑定和通用候选项选择本质上不是同一类功能，继续堆在一起会让后续维护越来越模糊。

### 2. 定义统一的交互选择 API

对外暴露一个统一函数，例如 `Select-InteractiveItem`。函数应支持：

- 字符串列表输入
- 对象列表输入
- 默认单选
- 通过显式参数开启多选
- 返回原始项本身，而不是索引或包装对象

对于对象输入，不做 `Name` / `Title` / `DisplayName` 之类的隐式字段猜测。调用方必须显式提供显示逻辑，例如：

- `-DisplayProperty Name`
- 或 `-DisplayScriptBlock { ... }`

这样可以把“显示文案长什么样”留在调用方上下文里，避免公共模块背负过多约定和猜测逻辑。

### 3. 优先 `fzf`，失败时自动降级到文本编号选择

选择流程分两层：

- 若检测到 `fzf`，使用 `fzf` 进行交互，单选/多选都走同一个主流程。
- 若未检测到 `fzf`，自动降级到纯文本编号列表，并使用 `Read-Host` 接受用户输入。

文本降级模式应覆盖：

- 单选：输入一个编号
- 多选：输入逗号分隔的多个编号
- 空输入/取消：返回 `$null` 或空数组
- 非法输入：提示重试或安全返回，不应导致整个脚本崩溃

该模块可以吸收 `Clean-DockerImages.ps1` 中现有的 `fzf` 安装提示和选择解析模式，但应改造成与“任意候选项列表”兼容的通用实现，而不是继续绑定 Docker 镜像字段结构。

### 4. 首先接入 benchmark 调度脚本

在 `scripts/pwsh/devops/Invoke-Benchmark.ps1` 中，当用户未提供 `Name` 参数时，不再直接报错，而是：

- 先扫描 `tests/benchmarks/*.Benchmark.ps1`
- 构建 benchmark 候选项对象
- 调用新的交互选择函数
- 用返回的原始项继续后续执行

如果用户显式提供 `Name`，则继续保留当前非交互调用路径，确保脚本依然适合自动化执行和命令行参数透传。

### 5. 为后续脚本复用预留清晰扩展面

这次计划不要求立刻把 `Clean-DockerImages.ps1` 等现有脚本全部迁移到新模块，但应保证 API 设计足够支撑后续迁移，例如：

- 支持字符串和对象两种输入
- 支持显示映射
- 支持单选/多选
- 支持取消返回空结果

这样 benchmark 完成首个接入后，后续其他脚本可以平滑迁移，而不需要再次重做接口。

## SpecFlow Analysis

从用户流角度，这次至少需要覆盖以下路径：

- **Flow 1: 用户直接运行 `pnpm benchmark` 或 `pnpm benchmark --`**
  - 系统扫描 benchmark 列表
  - 若存在 `fzf`，进入交互选择
  - 若不存在 `fzf`，自动降级到文本编号列表
  - 选择完成后执行对应 benchmark

- **Flow 2: 用户显式运行 `pnpm benchmark -- command-discovery -Iterations 2`**
  - 系统跳过交互
  - 继续按当前参数透传逻辑执行

- **Flow 3: 调用方传入对象候选项**
  - 调用方显式传入 `DisplayProperty` 或 `DisplayScriptBlock`
  - 模块只负责展示与返回，不参与对象领域逻辑

- **Flow 4: 用户取消选择**
  - 模块返回 `$null` 或空数组
  - 调用方自己决定是退出、提示还是重试

- **Flow 5: 文本降级下多选**
  - 用户输入 `1,3,5`
  - 模块正确解析、去重、保序并返回原始对象集合

由此得到的补充要求：

- 新模块不能只针对 `fzf` 做 happy path；文本降级本身就是核心功能，而不是附带兜底。
- benchmark 脚本需要明确处理“用户取消”返回值，否则调用链会在空结果上继续运行。

## Technical Considerations

- API 需要同时适配交互式和脚本式调用，不能为交互体验破坏非交互参数路径。
- `fzf` 检测建议优先复用现有仓库模式，而不是重新发明另一套环境探测逻辑。
- 文本降级实现应保持跨平台，不依赖 `Out-GridView` 等 GUI 能力。
- 对象显示逻辑必须显式指定，避免公共模块里塞入领域命名猜测，保持边界清晰。
- 需要谨慎处理返回值类型：单选时返回单个原始项，多选时返回原始项数组；取消时返回 `$null` 或空数组，不能用异常来表达正常取消。
- 这次不需要让新模块进入 Profile 同步加载路径，因为 benchmark 与脚本级交互不属于启动关键路径。

## System-Wide Impact

- **Interaction graph**：`Invoke-Benchmark.ps1` 在缺少 `Name` 参数时，将从“报错退出”改为“调用交互选择模块获取目标 benchmark”；显式指定 `Name` 的非交互路径保持不变。
- **Error propagation**：`fzf` 缺失不应被视为错误，而应进入文本降级；真正的失败应聚焦于候选项构建异常或目标脚本执行失败。
- **State lifecycle risks**：本次功能不持久化状态，不改缓存，不影响现有 benchmark 数据文件输出。
- **API surface parity**：新模块成为 `psutils` 的公共能力，但第一阶段只要求 benchmark 接入；`Clean-DockerImages.ps1` 等脚本可后续逐步迁移。
- **Integration test scenarios**：
  - benchmark 无参数且有 `fzf` 时，能成功进入交互路径。
  - benchmark 无参数且无 `fzf` 时，能进入编号列表降级路径。
  - benchmark 显式给定名称时，不触发交互选择。
  - 多选文本输入能正确解析并返回原始项集合。

## Acceptance Criteria

- [x] `psutils` 新增专用的交互选择模块，而不是继续把能力堆进 `functions.psm1`。
- [x] 新模块公开统一的交互选择 API，支持字符串列表和对象列表输入。
- [x] 新 API 默认单选，并通过显式参数支持多选。
- [x] 新 API 返回原始项本身；取消选择时返回 `$null` 或空数组，而不是抛错。
- [x] 对象输入时，调用方必须显式提供 `DisplayProperty` 或 `DisplayScriptBlock` 之类的显示逻辑。
- [x] 选择流程优先使用 `fzf`；无 `fzf` 时自动降级到文本编号列表 + `Read-Host`。
- [x] `scripts/pwsh/devops/Invoke-Benchmark.ps1` 在不传 `Name` 参数时，改为调用新模块进行选择，而不是直接报错让用户看 `--list`。
- [x] 显式传入 benchmark 名称时，现有非交互执行路径与参数透传行为保持不变。
- [x] 新增或更新测试，覆盖字符串输入、对象输入、文本降级、多选解析、取消返回值和 benchmark 接入。
- [x] 根目录 `pnpm qa` 通过。

## Success Metrics

- 用户运行 `pnpm benchmark` 时，不再需要先手工列出 benchmark 再复制名称，而是能直接被引导完成选择。
- 新交互选择能力可以在 benchmark 之外被其他脚本复用，而不需要再次复制 `fzf` 检测和降级逻辑。
- 公共模块边界保持清晰：交互选择属于独立模块，不继续膨胀 `functions.psm1`。

## Dependencies & Risks

- 风险：文本降级多选解析容易引入输入歧义或索引越界问题。
  缓解：把非法输入、重复编号、空输入、越界编号都纳入测试覆盖。

- 风险：benchmark 脚本可能把取消选择当成异常继续执行。
  缓解：在计划中明确要求 benchmark 调用方显式处理空返回值。

- 风险：若对象显示逻辑允许自动猜测字段，公共 API 会逐渐积累不可维护的隐式约定。
  缓解：坚持显式 `DisplayProperty` / `DisplayScriptBlock` 边界。

- 风险：仓库里已有 `fzf` 逻辑分散在多个脚本，第一次抽象时容易遗漏特定脚本里的细节需求。
  缓解：以 benchmark 为首个接入点，先沉淀稳定 API，再考虑迁移 `Clean-DockerImages.ps1`。

- 风险：仓库当前没有 `docs/solutions/` 可检索，本次无法复用历史总结。
  缓解：基于现有实现模式与当前需求直接规划，并将关键边界写入计划。

## Sources & References

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-interactive-selection-module-brainstorm.md`
  - 延续的关键决策：专用模块、默认单选可切多选、返回原始项、对象显示显式指定、优先 `fzf` 自动降级。
- **Existing fzf interaction patterns:** `psutils/modules/functions.psm1:119`, `psutils/modules/functions.psm1:251`
- **Existing script-local fzf helpers:** `scripts/pwsh/devops/Clean-DockerImages.ps1:208`, `scripts/pwsh/devops/Clean-DockerImages.ps1:224`, `scripts/pwsh/devops/Clean-DockerImages.ps1:230`
- **Current benchmark dispatcher behavior:** `scripts/pwsh/devops/Invoke-Benchmark.ps1:27`, `scripts/pwsh/devops/Invoke-Benchmark.ps1:88`, `scripts/pwsh/devops/Invoke-Benchmark.ps1:100`
- **psutils export surface:** `psutils/psutils.psd1:80`, `psutils/psutils.psd1:98`, `psutils/psutils.psd1:112`
- **Institutional learnings search:** 未发现 `docs/solutions/` 目录，本次未检索到可复用的历史方案
- **External research:** 当前代码库已有明确模式，本次 planning 未额外引入外部资料
