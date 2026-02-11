## ADDED Requirements

### Requirement: Unified package QA script contract
系统 SHALL 为纳入范围的 workspace 子包提供统一 QA 脚本契约，至少包含 `typecheck:fast`、`check`、`test:fast`、`qa` 四个脚本。

#### Scenario: 子包脚本契约可发现
- **WHEN** 开发者查看目标子包 `package.json` 的 `scripts`
- **THEN** 可看到 `typecheck:fast`、`check`、`test:fast`、`qa` 四个标准脚本名

### Requirement: Consistent qa pipeline semantics
各子包 `qa` SHALL 按固定顺序执行 `typecheck:fast`、`check`、`test:fast`，并在任一步骤失败时返回非零退出码。

#### Scenario: qa 顺序一致且可失败快返
- **WHEN** 用户运行任一目标子包的 `pnpm run qa`
- **THEN** 工具按 `typecheck:fast -> check -> test:fast` 顺序执行，并在失败步骤立即终止且返回失败

### Requirement: Check command separates validation and fix
系统 SHALL 提供无副作用的 `check` 与可写入修复的 `check:fix`，其中 `check` 仅执行校验，`check:fix` 执行自动修复。

#### Scenario: check 不写盘
- **WHEN** 用户运行 `pnpm run check`
- **THEN** 仅执行 lint/format 校验而不修改源文件

#### Scenario: check:fix 可写盘修复
- **WHEN** 用户运行 `pnpm run check:fix`
- **THEN** 对可自动修复的问题执行写入修复

### Requirement: Pre-commit JS/TS lint and format convergence
系统 SHALL 在提交阶段对 JS/TS/CSS/HTML/JSON 等文件执行 `biome check --write`，使 lint 与格式化在同一入口收敛。

#### Scenario: 提交前统一修复
- **WHEN** 用户提交包含 JS/TS 相关改动的暂存文件
- **THEN** `lint-staged` 触发 `biome check --write` 并在提交前完成可自动修复项

### Requirement: Deterministic color behavior in fast tests
系统 SHALL 在相关 Vitest 配置中统一颜色环境，确保颜色相关断言在默认 QA 路径下稳定执行。

#### Scenario: 默认 qa 下颜色断言稳定
- **WHEN** 用户在默认环境运行子包 `pnpm run qa`
- **THEN** 颜色相关测试不依赖额外命令行环境变量即可稳定通过

### Requirement: Turbo-ready script interface for phase two
系统 SHALL 保持统一脚本接口与执行语义稳定，使 V2 可在不改动包内脚本名的前提下接入 Turborepo 调度。

#### Scenario: V2 可无缝接入调度层
- **WHEN** 后续在 V2 新增 `turbo run qa` 或 affected 调度命令
- **THEN** 子包无需重命名既有 `qa` 相关脚本即可被统一编排

### Requirement: Parallel Turbo QA entry without breaking legacy commands
系统 SHALL 在保留既有 `qa` 命令族行为不变的前提下，新增并行 Turbo 命令入口（`turbo:qa`、`turbo:qa:all`、`turbo:qa:verbose`、`turbo:qa:all:verbose`）。

#### Scenario: Turbo 并行入口可用且旧入口不破坏
- **WHEN** 用户查看根 `package.json` 的 `scripts`
- **THEN** 同时可见既有 `qa` 命令族与新增 `turbo:qa` 命令族

#### Scenario: Turbo changed 模式可按需跳过 workspace
- **WHEN** 用户运行 `pnpm turbo:qa` 且 workspace 路径无变更
- **THEN** 工具跳过 workspace `qa` 调度，并保持 root `qa:pwsh` 的既有探测行为

### Requirement: Consistent affected baseline between pnpm QA and Turbo QA
系统 SHALL 让 Turbo changed 模式复用 `QA_BASE_REF` 约定，并将其映射到 `TURBO_SCM_BASE`，默认基线为 `origin/master`。

#### Scenario: 基线变量映射一致
- **WHEN** 用户设置 `QA_BASE_REF` 后运行 `pnpm turbo:qa`
- **THEN** Turbo 以同一基线比较变更范围，而不要求用户额外设置另一套基线变量

### Requirement: CI history prerequisite for affected accuracy
系统 SHALL 在 CI 中保证 affected 计算所需的 Git 历史完整性（例如 `actions/checkout` 使用 `fetch-depth: 0`）。

#### Scenario: CI checkout 提供完整历史
- **WHEN** CI 运行 Turbo affected 相关命令
- **THEN** checkout 步骤提供足够历史以避免“全部包被误判为受影响”

### Requirement: Performance baseline is recorded, not hard-gated
系统 SHALL 记录 V1 与 V2 在 `cold(all)`、`warm(all)`、`changed(PR)` 三类场景的耗时与可观测性指标，但 SHALL NOT 将“V2 必须快于 V1”作为硬性正确性门槛。

#### Scenario: 性能结果可追溯
- **WHEN** 完成一轮 V1/V2 对比执行
- **THEN** `validation.md` 包含至少耗时、缓存命中率、最长耗时包与失败定位可读性结论
