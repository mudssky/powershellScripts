---
title: refactor: align pwsh test commands
type: refactor
status: completed
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-pwsh-test-command-alignment-brainstorm.md
---

# refactor: align pwsh test commands

## Overview

整理根目录 `package.json` 中所有 PowerShell / Pester 相关测试命令，将命名统一收敛到 `test:pwsh:*` 语义下，并新增跨环境聚合入口 `test:pwsh:all`，用于在提交前并发执行 host 与 Linux 容器两套完整 PowerShell 测试（see brainstorm: `docs/brainstorms/2026-03-14-pwsh-test-command-alignment-brainstorm.md`）。

本计划同时约束三件事：一是命令命名不再混合“测试域 / 平台 / 质量门”三种语义；二是 `qa` / `qa:all` 保持快速质量门定位，不被重型跨环境测试绑死；三是 `AGENTS.md`、README 与本地测试文档必须一起迁移，确保“改动 pwsh 相关内容时，提交代码前执行 `pnpm test:pwsh:all`”成为清晰、可执行的协作约定。本次作用域只覆盖 root PowerShell 测试命令，不调整 workspace 包内既有 `test:fast` / `qa` 契约。

## Problem Statement / Motivation

当前命令层存在明显语义混杂：

- `test:full`、`test:fast`、`test:qa` 没有体现这是 PowerShell / Pester 测试。
- `test:linux` 只表达了平台，但实际执行的是 Linux 容器中的快速 Pester 集合，不包含“测试域”和“强度”信息。
- `qa:pwsh` 依赖 `test:qa`，而 `qa` / `qa:all` 又是另一层聚合质量门，容易让开发者误以为 `qa:all` 已经覆盖提交前的完整跨环境 pwsh 回归。

仓库已经有两个重要现状需要被保留：

- `docs/plans/2026-03-05-qa-speed-design.md` 已明确把 `qa` 设计为快速、降噪、本地可频繁运行的质量门，不应该因为这次命名整理被重新塞回重测试。
- `docs/local-cross-platform-testing.md` 与 `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md` 都说明，PowerShell 测试在 Linux/macOS 下很容易暴露 Windows 本机看不到的问题，因此提交前确实需要一个明确的跨环境验证入口。

## Proposed Solution

### 1. 将 PowerShell 测试命令统一收敛到 `test:pwsh:*`

把当前根目录 `package.json` 中所有直接面向 Pester 的命令迁移到统一命名空间下，至少包括：

- `test:pwsh:fast`
- `test:pwsh:full`
- `test:pwsh:qa`
- `test:pwsh:serial`
- `test:pwsh:debug`
- `test:pwsh:serial:debug`
- `test:pwsh:profile`
- `test:pwsh:slow`
- `test:pwsh:detailed`
- `test:pwsh:linux:fast`
- `test:pwsh:linux:full`
- `test:pwsh:linux:build`

旧的 `test`、`test:fast`、`test:full`、`test:qa`、`test:linux`、`test:linux:full`、`test:linux:build` 等 root 旧命令直接移除，不提供兼容别名。这样开发者看到命令名时，可以先判断“这是 PowerShell 测试”，再判断具体强度与运行环境，而不是反向猜测。

### 2. 新增 `test:pwsh:all` 作为提交前的跨环境完整验证入口

新增 `test:pwsh:all`，并使用 `concurrently` 并发执行：

- `pnpm test:pwsh:full`
- `pnpm test:pwsh:linux:full`

这里的核心目标不是替代 `qa`，而是给“改动 pwsh 相关内容后、准备提交前”的场景提供一条高信号命令。并发执行的原因有两点：

- 当前 host 与 Linux 容器测试的结果输出已经隔离，具备安全并发基础（`docs/local-cross-platform-testing.md`）。
- 近期 Linux/macOS 工具链测试踩坑已证明，单跑 Windows 本机不能代表跨平台稳定性（see: `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`）。

`test:pwsh:all` 需要具备明确的标签化输出和 fail-fast 行为，让开发者能快速区分 host / linux 哪一路失败，并在任一路失败时返回非零退出码。

### 3. 保持 `qa` / `qa:all` 的职责边界不变

这次调整不应把 `qa` 重型化。计划应明确：

- `qa:pwsh` 仍然是 root PowerShell 侧快速质量门。
- `qa:pwsh` 内部从旧的 `test:qa` 切换到新的 `test:pwsh:qa`。
- `qa` / `qa:all` / `turbo:qa*` 的语义保持不变，继续服务“快速反馈”而不是“提交前完整跨环境回归”。

这条边界直接承接 2026-03-05 的 QA 提速设计，避免新命名让团队误以为 `qa:all` 等于 `test:pwsh:all`。

### 4. 同步迁移文档与协作约定

除 `package.json` 外，至少同步更新以下活文档：

- `README.md`
- `CLAUDE.md`
- `docs/local-cross-platform-testing.md`
- `AGENTS.md`

文档更新应覆盖：

- 新命令名与旧命令名的替换
- `test:pwsh:all` 的用途说明
- Docker / `concurrently` 依赖说明
- Docker 不可用时的 fallback 说明
- “改动 pwsh 相关内容时，提交前执行 `pnpm test:pwsh:all`” 的团队协作约定
- “哪些改动算 pwsh 相关”的路径或文件类型示例，例如 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`

历史档案类文档（例如 `docs/solutions/**`、`openspec/changes/archive/**`）不作为本次批量回写目标，避免把命名迁移扩散成一次无收益的大范围文档重写。

## SpecFlow Analysis

从开发者工作流看，至少要覆盖以下用户流与失败流：

- **Flow 1: 日常本机快速迭代**
  - 开发者只想在本机快速回归 PowerShell 改动
  - 能直接从命令名判断该用 `test:pwsh:fast` 或 `qa:pwsh`
  - 不会误把 `qa` 当成完整跨环境验证

- **Flow 2: 提交前完整验证**
  - 开发者修改了 `scripts/pwsh/**`、`profile/**`、`psutils/**` 或相关测试
  - 根据 `AGENTS.md` 约定执行 `pnpm test:pwsh:all`
  - 一次命令内同时覆盖 host `full` 与 Linux 容器 `full`

- **Flow 3: Linux 路径暴露平台假设**
  - Windows 本机通过，但 Linux 容器下因为 PATH、shebang、`PATHEXT`、工具 mock 或安装提示差异失败
  - `test:pwsh:all` 应能把这类问题提前到提交前，而不是只留给 CI 发现

- **Flow 4: Docker 不可用**
  - 开发者本机未安装 Docker 或 Docker daemon 未启动
  - 文档需要明确说明 `test:pwsh:all` 的依赖与 fallback，不让失败表现成“命令无缘无故坏了”

- **Flow 5: QA 与提交前校验并存**
  - 开发者平时继续运行 `pnpm qa`
  - 提交前只在 pwsh 相关改动时额外运行 `pnpm test:pwsh:all`
  - 两条路径互补，而不是相互覆盖

由此得到的补充要求：

- 计划必须清楚界定“哪些改动算 pwsh 相关”，至少在文档或 AGENTS 里给出路径示例。
- 计划必须要求所有 root 旧命令引用一起迁移，否则 README / 本地文档 / 协作约定会长期互相冲突。
- 计划必须覆盖 `test:pwsh:all` 的失败可读性，否则并发后日志更难排查。
- 计划必须明确作用域只在 root，避免误伤 workspace 包内 `test:fast` 与 `qa` 标准契约。

## Technical Considerations

- 仓库当前未发现 `concurrently` 依赖，因此计划需要补充 devDependency，并决定脚本中使用直接命令还是 `pnpm exec concurrently`。
- 并发执行的前提已经基本具备：host 测试输出 `testResults.xml`，Linux 容器输出隔离在 named volume 中，默认不会发生结果文件冲突（`docs/local-cross-platform-testing.md`）。
- Linux 侧底层仍然复用 `docker compose -f docker-compose.pester.yml run --rm pester-full`，也就是说平台运行方式不会改变，只是命令名与聚合入口改变。
- 文档与脚本必须同步迁移，否则会出现 `package.json` 已改名、README / AGENTS 仍然指导开发者运行旧命令的断层。
- `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md` 说明 Linux/macOS 会暴露 Windows 假设，因此 `test:pwsh:all` 不应退化为“串起两个名字好看一点的脚本”，而要继续保证 Linux 路径是实际执行的。
- OpenSpec 已将“host 与 Linux 容器并存”“并发运行避免 artifact 冲突”“full 模式可在提交前执行”定义为正式约束，因此本次命名迁移应复用这些既有语义，而不是重新定义测试流程本身。
- `qa` 相关脚本本身不需要重写调度逻辑，只需确保 `qa:pwsh` 指向新的 `test:pwsh:qa`，保持现有 `scripts/qa.mjs` / `scripts/qa-turbo.mjs` 行为稳定。

## System-Wide Impact

- **Interaction graph**：开发者执行 `pnpm test:pwsh:all` 时，会并发触发 host `Invoke-Pester` 与 Linux Docker Compose Pester；开发者执行 `pnpm qa` 时，仍经由 `qa:pwsh -> test:pwsh:qa` 走快速链路。
- **Error propagation**：`test:pwsh:all` 任一路失败都应返回非零退出码；输出需要能区分 host / linux，避免并发日志把真实失败源淹没。
- **State lifecycle risks**：并发测试不应争用同一个测试结果文件；如需调整结果路径、容器 volume 或日志前缀，应一并纳入实现。
- **API surface parity**：所有面向开发者的入口都要同步迁移，包括 `package.json`、README、CLAUDE、本地测试文档与 AGENTS；不允许“脚本已改名但文档仍写旧命令”的双轨状态。
- **Integration test scenarios**：
  - `pnpm test:pwsh:full` 单独通过
  - `pnpm test:pwsh:linux:full` 单独通过
  - `pnpm test:pwsh:all` 并发执行时日志可区分 host / linux，且退出码正确
  - `pnpm qa` 仍保持快速质量门语义
  - Docker 不可用时，开发者能从文档或脚本输出中明确知道 fallback 路径

## Acceptance Criteria

- [x] 根目录 `package.json` 中所有 PowerShell / Pester 测试命令都收敛到 `test:pwsh:*` 命名空间。
- [x] 这次改动只调整 root PowerShell 测试命令，不修改 workspace 包内既有 `test:fast` / `qa` 契约。
- [x] 旧的 `test`、`test:fast`、`test:full`、`test:qa`、`test:linux`、`test:linux:full`、`test:linux:build` 等 root 旧命令不再保留为兼容别名。
- [x] 新增 `test:pwsh:all`，并发执行 `test:pwsh:full` 与 `test:pwsh:linux:full`。
- [x] `test:pwsh:all` 输出能清晰标识 host / linux 两路执行结果，并在任一路失败时返回非零退出码。
- [x] `qa:pwsh` 改为调用 `test:pwsh:qa`，而 `qa` / `qa:all` / `turbo:qa*` 的职责边界保持不变。
- [x] `README.md`、`CLAUDE.md`、`docs/local-cross-platform-testing.md` 与 `AGENTS.md` 全部迁移到新命名，不再保留旧命令引用。
- [x] `AGENTS.md` 明确写出：改动 pwsh 相关内容时，提交代码前执行 `pnpm test:pwsh:all`，并给出至少一组路径或文件类型示例。
- [x] 文档明确说明 `test:pwsh:all` 依赖 Docker；当 Docker 不可用时，给出至少运行 host 完整测试并依赖 CI 补 Linux 验证的 fallback 指引。
- [x] 根目录 `pnpm qa` 通过。

## Success Metrics

- 开发者首次看到命令名即可判断“测试域 / 环境 / 强度”，无需再从实现倒推语义。
- 提交前针对 pwsh 改动的标准动作收敛为一条命令：`pnpm test:pwsh:all`。
- `qa` 与 `test:pwsh:all` 的职责边界清晰，团队不会再把 `qa:all` 误认为完整跨环境 pwsh 回归。
- 本地文档、协作约定与实际脚本名保持一致，不再出现旧命令与新命令并存的指导冲突。

## Dependencies & Risks

- 风险：不保留旧命名别名会直接打断已有使用习惯。
  缓解：一次性同步更新 README、CLAUDE、本地测试文档与 AGENTS，并在变更说明中显式列出新旧映射。

- 风险：`test:pwsh:all` 依赖 Docker，本地无 Docker 的开发者会被新协作约定卡住。
  缓解：在文档中明确 Docker 依赖与 fallback，必要时让命令输出给出清晰错误而不是原始 Docker 噪音。

- 风险：并发执行后日志交错，失败源更难定位。
  缓解：通过 `concurrently` 的命名、颜色和 fail-fast 选项保持输出可读性。

- 风险：只改脚本不改文档，会让 2026-03-05 的 QA 设计和 2026-03-14 的跨平台测试文档失真。
  缓解：把 README、`docs/local-cross-platform-testing.md`、AGENTS、CLAUDE 作为同一批改动的一部分。

- 风险：如果实现时顺手把 `qa` 也抬成重测试，会回退此前的 QA 提速成果。
  缓解：在计划与验收标准中明确 `qa` 的快速质量门边界不变。

## Sources & References

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-pwsh-test-command-alignment-brainstorm.md`
  - 延续的关键决策：PowerShell 测试命名收敛到 `test:pwsh:*`；新增 `test:pwsh:all`；不新增 `ci:check`；不保留旧命名兼容层；提交前 pwsh 改动执行 `pnpm test:pwsh:all`。
- **Current command surface:** `package.json`
- **Current QA boundary:** `docs/plans/2026-03-05-qa-speed-design.md`
- **Local cross-platform testing guide:** `docs/local-cross-platform-testing.md`
- **Cross-platform failure learnings:** `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`
- **Formal workflow constraints:** `openspec/specs/local-cross-platform-pester-testing/spec.md`, `openspec/specs/pester-test-performance/spec.md`, `openspec/specs/workspace-qa-standardization/spec.md`
- **Existing contributor guidance:** `AGENTS.md`, `README.md`, `CLAUDE.md`
- **Linux container harness:** `docker-compose.pester.yml`, `Dockerfile.pester`, `PesterConfiguration.ps1`
- **External research:** 基于强本地上下文与已存在文档，本次计划未额外引入外部资料
