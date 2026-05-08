# brainstorm: 拆分 pnpm workspace 包

## Goal

评估当前仓库是否应该拆分更多 pnpm workspace 包，并让 Trellis 的 package/spec 边界与真实项目边界对齐，从而让不同类型项目获得更准确的规范、QA 路由与上下文注入。

## What I already know

* 用户关注点是：是否可以按 Trellis 流程把项目拆成更多 pnpm workspace 包，让不同项目规范更好区分。
* 当前 `pnpm-workspace.yaml` 只包含 `projects/**` 和 `scripts/node`。
* 当前 pnpm workspace 实际覆盖的包包括：
  * `projects/clis/pwshfmt-rs`
  * `projects/clis/json-diff-tool`
  * `scripts/node`
  * `config/software/mpv/mpv_scripts`
* 当前 `.trellis/config.yaml` 只声明了一个 Trellis package：`node-script -> scripts/node`，且 `default_package` 也是 `node-script`。
* `python ./.trellis/scripts/get_context.py --mode packages` 只列出 `node-script`，说明 Trellis 规范上下文还没有覆盖已有多个 workspace 包。
* 仓库中存在多个天然项目域：`scripts/pwsh`、`profile`、`psutils`、`scripts/bash`、`scripts/python`、`scripts/ahk`、`linux/*`、`ai/*`、`config/*`、`projects/clis/*`。
* 根目录 `package.json` 已经集中编排跨语言 QA，例如 PowerShell/Pester、bash/Vitest、fnos、systemd service manager、Rust formatter CLI、Node CLI 等。
* Turbo 已配置 `typecheck:fast`、`check`、`test:fast`、`qa` 任务图，适合 workspace 包拥有一致的脚本接口后获得更清楚的 affected/缓存边界。
* pnpm 官方文档说明：`pnpm-workspace.yaml` 通过 `packages` 字段包含或排除目录；根 package 总是 workspace 的一部分；未设置 `packages` 时仅包含根 package。

## Assumptions (temporary)

* 这次任务先做架构/规范拆分设计，不直接迁移源码。
* 拆分目标不是让每个目录都有 `package.json`，而是让“独立 QA、依赖、发布/构建或 Trellis 规范边界”的目录成为包。
* PowerShell 模块与 profile 可能需要比普通 Node workspace 更谨慎，因为它们有 Pester 配置、覆盖率与跨平台测试约束。

## Open Questions

* 无。

## Requirements (evolving)

* 识别当前 workspace 与 Trellis package 的不一致点。
* 给出 2-3 种可行拆分策略，并说明收益与风险。
* 明确哪些目录适合优先拆为包，哪些目录暂时只适合建立 Trellis spec 而不是 pnpm package。
* 采用 Approach B：按 QA/语言域新增 workspace 包，并同步已有 pnpm workspace 包与 Trellis package/spec。
* 第一层对齐已有 workspace 包：`scripts/node`、`projects/clis/json-diff-tool`、`projects/clis/pwshfmt-rs`、`config/software/mpv/mpv_scripts`。
* 第二层新增具备独立 QA 或清晰语言域的 workspace 包：`scripts/bash`、`scripts/pwsh`、`psutils`。
* 第一批不包含 `linux/fnos`；该目录保留到后续批次单独评估。
* 实施时同步更新 pnpm workspace、Trellis package 配置、QA 路由和必要 spec。

## Acceptance Criteria

* [x] 有一份明确的拆包建议，能解释为什么拆、拆哪里、暂不拆哪里。
* [x] 方案能兼容现有根目录 `pnpm qa`、`pnpm test:pwsh:all` 等质量门槛。
* [x] 方案能让 Trellis `get_context.py --mode packages` 输出更贴近真实项目域。
* [x] 若实施，新增/调整的包具备最小可用脚本接口，例如 `qa`、`test:fast`、`check` 或明确无需脚本的理由。
* [x] `scripts/bash` 的包边界复用现有 `pnpm test:bash` / `pnpm qa:bash` 语义。
* [x] PowerShell 相关包边界不破坏现有 Pester 模式、coverage 与 `pnpm test:pwsh:all` 规则。

## Definition of Done (team quality bar)

* Tests added/updated where behavior changes.
* Lint / typecheck / CI green.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Research References

* Context7 pnpm docs `/websites/pnpm_io` — `pnpm-workspace.yaml` 通过 `packages` 字段定义 workspace 包匹配模式，支持通配与排除；根 package 始终属于 workspace。

## Research Notes

### Constraints from our repo/project

* Trellis package 边界目前落后于 pnpm workspace 边界：已有多个 pnpm 包，但 Trellis 只识别 `node-script`。
* 根 QA 编排已经承担跨项目职责，拆包后要避免让根 QA 与包级 QA 重复、遗漏或语义冲突。
* `scripts/pwsh`、`profile`、`psutils` 的测试与覆盖率规则更特殊，不宜只为“形式统一”仓促塞进普通 Node 包模型。
* `scripts/bash` 已有 `vitest.config.ts`、`tests/` 和 `systemd-service-manager` 子测试入口，适合先抽出包级 QA。
* `linux/fnos` 当前测试入口指向 `linux/fnos/fnos-mount-manager/vitest.config.ts`，边界更像具体子项目而不是整个 `linux` 域。

### Feasible approaches here

**Approach A: Trellis-first 对齐已有 workspace 包**（推荐 MVP）

* How it works: 先不大规模新增 `package.json`，只把已有 pnpm 包同步进 `.trellis/config.yaml`，并为 `json-diff-tool`、`pwshfmt-rs`、`mpv_scripts`、`node-script` 建立对应 spec 边界。
* Pros: 改动小，能立刻解决 Trellis 上下文不准的问题；风险低，不扰动 QA。
* Cons: 对 `scripts/pwsh`、`profile`、`psutils` 等大目录的规范隔离还不完整。

**Approach B: 按 QA/语言域新增 workspace 包**

* How it works: 在 Approach A 基础上，把 `scripts/bash`、`scripts/pwsh`、`psutils`、必要时 `linux/fnos` 等具备独立测试入口的目录逐步加成 workspace 包，并统一 `qa` / `test:fast` / `check` 脚本契约。
* Pros: Turbo affected 与包级 QA 边界更清楚；Trellis spec 能按语言/运行时注入。
* Cons: 需要调整根 QA、测试路径和脚本约定；PowerShell 覆盖率与 Linux/Docker 测试要特别设计。
* Decision: 用户已选择本方向作为目标方案。

**Approach C: 全域目录包化**

* How it works: 尽量让 `ai/*`、`config/*`、`docs`、`templates`、各类脚本目录都成为 workspace 包或类包单元。
* Pros: 边界形式最统一。
* Cons: 很多配置/文档目录没有 Node 包语义，会制造空脚本和维护成本；容易把 pnpm workspace 当成目录索引，而不是构建/依赖/QA 边界。

## Expansion Sweep

### Future evolution

* 未来可让 Trellis spec 按 `pwsh-tooling`、`node-cli`、`rust-cli`、`infra-config`、`docs` 等域自动注入，减少 AI 修改跨语言仓库时上下文串味。
* 若 Turbo affected 成为主 QA 入口，包级脚本契约需要稳定下来，避免新增包后 QA 语义漂移。

### Related scenarios

* OpenSpec/Trellis 任务创建时的 `--package` 选择应能覆盖真实项目域。
* 根 `pnpm qa`、`pnpm qa:all`、`pnpm turbo:qa` 与包级 `qa` 要保持一致的失败语义。

### Failure & edge cases

* 新增 workspace pattern 可能把不该纳入的临时目录、嵌套 fixture 或配置示例误纳入 workspace。
* 没有 `qa` 脚本的包可能导致 Turbo 或递归 pnpm 命令行为不一致。
* PowerShell/Pester 相关包如果拆得太细，可能破坏现有集中 coverage 门槛。

## Technical Notes

* Inspected `pnpm-workspace.yaml`。
* Inspected root `package.json`。
* Inspected `.trellis/config.yaml`。
* Inspected `.trellis/spec/*`。
* Ran `python ./.trellis/scripts/get_context.py --mode packages`。
* Inspected package files under `projects/clis/*`, `scripts/node`, `config/software/mpv/mpv_scripts`。
* Inspected root QA orchestrators `scripts/qa.mjs` and `scripts/qa-turbo.mjs` at a high level.
* Inspected QA path references for `scripts/bash`, `scripts/pwsh`, `psutils`, and `linux/fnos`.

## Technical Approach

采用按 QA/语言域拆分的渐进方案：先让已有 pnpm workspace 包在 Trellis 中具名，再为具备独立测试入口的目录新增 workspace 包与 spec 边界。PowerShell 相关目录暂时以共享 Pester 质量门槛为核心，包级脚本只包装现有根命令，不先改覆盖率策略。

## Decision (ADR-lite)

**Context**: 仓库已经是跨语言脚本集合，根 QA 同时管理 Node、Rust、PowerShell、Bash、Linux 子项目；但 Trellis 目前只知道 `node-script`，导致规范注入粒度过粗。

**Decision**: 选择 Approach B，按 QA/语言域新增 workspace 包，并同步已有 workspace 包到 Trellis package/spec。

**Consequences**: 规范隔离和 Turbo affected 边界会更清楚；代价是需要统一包级脚本契约，并谨慎处理 PowerShell/Pester 的集中 coverage 规则。

## Implementation Plan (small PRs)

* PR1: 对齐已有 workspace 包与 Trellis package/spec，确保 `get_context.py --mode packages` 能列出真实已有包。
* PR2: 新增 `scripts/bash`、`scripts/pwsh`、`psutils` 的 workspace 包边界与最小脚本契约，包级脚本提供手动包装入口但不暴露 `qa` / `test:fast`，避免改变根 QA 自动执行范围。
* PR3: 调整根 QA/Turbo 路由与 Trellis context 配置，验证 `pnpm qa`、PowerShell 相关测试规则和包列表输出。

## Verification Notes

* 已运行 `python ./.trellis/scripts/get_context.py --mode packages`，确认 Trellis 能发现 7 个 package 及对应 spec layer。
* 已运行 `pnpm -r list --depth -1 --parseable`，确认 pnpm 能发现根项目加 7 个 workspace 包。
* 已用 Node 解析新增/调整的 `package.json`，确认 JSON 格式有效。
* 已运行 `python ./.trellis/scripts/task.py validate .trellis/tasks/05-08-split-pnpm-workspace-packages`，确认任务上下文 JSONL 有效。
* 按用户要求，本次只改配置和文档，未运行 `pnpm qa` 或业务测试。

## Out of Scope (explicit)

* 暂不迁移源码目录。
* 暂不修改测试覆盖率门槛。
* 暂不为纯文档/配置目录强制创建 Node package，除非后续决定需要独立 QA 或发布边界。
* 第一批暂不纳入 `linux/fnos`。
