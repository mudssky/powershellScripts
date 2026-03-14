---
status: complete
priority: p2
issue_id: "001"
tags: [powershell, psutils, benchmark, fzf]
dependencies: []
---

# 交互选择模块与 benchmark 接入

## Problem Statement

`Invoke-Benchmark.ps1` 在缺少 `Name` 参数时直接报错，用户必须先手工执行 `--list` 再复制 benchmark 名称，交互体验较弱。同时，仓库内与 `fzf` 相关的选择逻辑已经分散在 `functions.psm1` 与 `Clean-DockerImages.ps1` 中，缺少可复用的统一模块。

## Findings

- `scripts/pwsh/devops/Invoke-Benchmark.ps1` 当前仅支持显式 `Name` 或 `--list`，缺少交互选择路径。
- `scripts/pwsh/devops/Clean-DockerImages.ps1` 已包含 `fzf` 检测、安装提示与多选解析模式，可作为模块设计参考。
- `psutils/psutils.psd1` 通过 `NestedModules` 与 `FunctionsToExport` 管理公共接口，新增模块需要同时接入这两个位置。
- `psutils/tests` 与 `tests` 已存在 Pester 测试基础设施，适合分别覆盖模块级行为与 benchmark 脚本接入行为。

## Proposed Solutions

### Option 1: 仅在 benchmark 脚本内局部实现交互

**Approach:** 直接在 `Invoke-Benchmark.ps1` 内加入 `fzf` 和文本编号选择逻辑。

**Pros:**
- 改动面最小
- 可以最快让 benchmark 可交互

**Cons:**
- 无法复用
- 会继续复制 `fzf` 与降级逻辑

**Effort:** 1-2 小时

**Risk:** Medium

---

### Option 2: 新增 `psutils` 交互选择模块并接入 benchmark

**Approach:** 在 `psutils/modules/selection.psm1` 中实现统一选择 API，通过 manifest 导出，并让 benchmark 脚本调用它。

**Pros:**
- 复用边界清晰
- 可同时覆盖 `fzf` 与文本降级
- 后续脚本迁移成本低

**Cons:**
- 需要同步修改 manifest 与测试
- 首次抽象需要验证接口稳定性

**Effort:** 2-4 小时

**Risk:** Low

## Recommended Action

采用 Option 2：新增独立交互选择模块，保持对象显示逻辑显式传入，优先使用 `fzf`，在缺失时自动降级到文本编号选择，并首先接入 benchmark 调度脚本。

## Technical Details

**Affected files:**
- `psutils/modules/selection.psm1`
- `psutils/psutils.psd1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- `psutils/tests/selection.Tests.ps1`
- `tests/Invoke-Benchmark.Tests.ps1`
- `docs/plans/2026-03-14-003-feat-interactive-selection-module-plan.md`

**Related components:**
- `scripts/pwsh/devops/Clean-DockerImages.ps1`
- `psutils/modules/functions.psm1`

**Database changes (if any):**
- 无

## Resources

- `docs/plans/2026-03-14-003-feat-interactive-selection-module-plan.md`
- `docs/brainstorms/2026-03-14-interactive-selection-module-brainstorm.md`
- `scripts/pwsh/devops/Clean-DockerImages.ps1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`

## Acceptance Criteria

- [x] `psutils` 提供独立的交互选择模块与统一 API。
- [x] API 支持字符串与对象输入，并在对象输入时要求显式显示逻辑。
- [x] API 默认单选，支持显式多选，并返回原始项本身。
- [x] `fzf` 缺失时自动降级到文本编号选择。
- [x] benchmark 无参数时改为交互选择，并显式处理取消返回值。
- [x] 新增测试覆盖模块行为与 benchmark 接入。
- [x] 根目录 `pnpm qa` 通过。

## Work Log

### 2026-03-14 - 执行初始化

**By:** Codex

**Actions:**
- 读取执行计划、brainstorm 与相关引用文件。
- 对齐 `Clean-DockerImages.ps1`、`functions.psm1`、`psutils.psd1` 与现有 Pester/QA 结构。
- 创建功能分支 `feat/interactive-selection-module`。
- 建立文件化 todo，作为本次执行记录。

**Learnings:**
- 现有 QA 会自动包含新增 `psutils/modules/*.psm1` 对应的 `psutils/tests/*.Tests.ps1`。
- benchmark 脚本测试更适合放在根级 `tests/`，模块行为测试放在 `psutils/tests/`。

### 2026-03-14 - 实现与验证完成

**By:** Codex

**Actions:**
- 新增 `psutils/modules/selection.psm1`，实现 `fzf` 优先、文本编号降级、单选/多选与对象显示映射。
- 更新 `psutils/psutils.psd1`，将 `selection.psm1` 与 `Select-InteractiveItem` 接入标准导出面。
- 改造 `scripts/pwsh/devops/Invoke-Benchmark.ps1`，在缺少 `Name` 时走交互选择，并支持测试用目录覆盖。
- 新增 `psutils/tests/selection.Tests.ps1` 与 `tests/Invoke-Benchmark.Tests.ps1`，覆盖文本降级、对象输入、取消返回值、`fzf` 路径与 benchmark 集成。
- 执行根目录 `pnpm qa`，确认格式化与 QA 测试全部通过。

**Learnings:**
- `Get-Command` 用于 `fzf` 探测会放大命令发现开销，改为轻量 PATH 探测后模块与测试都更稳定。
- benchmark 集成测试需要为每个用例隔离独立的 `TestDrive` 子目录，否则会互相污染候选脚本列表。

## Notes

- 本次只要求 benchmark 首先接入，不强制迁移 `Clean-DockerImages.ps1`。
