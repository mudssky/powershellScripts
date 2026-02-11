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
