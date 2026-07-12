# PsUtils Package Guidelines

> 适用于 `psutils` PowerShell 模块、模块源码、示例、文档和模块内 Pester 测试。

## Scope

* 包路径：`psutils`
* Workspace 包名：`psutils`
* 主要入口：`psutils/package.json`
* 规范模块入口：`psutils/psutils.psd1`；`psutils/index.psm1` 仅为弃用兼容 shim，新代码不得依赖它。

## Pre-Development Checklist

* 模块源码应优先放在 `psutils/modules` 或既有 `psutils/src` 结构中，不要从根目录新增平行模块目录。
* 修改配置解析、env 读取、frontmatter、`.psd1` data file 或 CLI 参数合并时，先阅读 [Shared Config Resolver](./shared-config-resolver.md)。
* Pester 运行方式复用 `scripts/pwsh/devops/Invoke-PesterMode.ps1`，包内脚本通过 `PWSH_TEST_PATH` 限定 `./tests`。
* 覆盖率门槛仍由根目录 `PesterConfiguration.ps1` 统一管理；包级 `test:full` 只做断言回归，不单独改 coverage 策略。
* 修改 WSL Docker wrapper 或 docker 参数路径转换时，先阅读 [WSL Docker Wrapper](./wsl-docker-wrapper.md)。
* NestedModules 之间不共享彼此的私有 session state。模块调用另一个模块导出的函数时，必须在自身作用域按需导入直接依赖；不能只依赖调用方已经导入聚合 `psutils` manifest。
* 修改 manifest、NestedModules、公共导出或兼容入口时，先阅读 [Module Entry Contract](./module-entry-contract.md)，并同步 `psutils/tests/moduleContract.Tests.ps1`。

## Package Script Contract

* `test:qa` 运行包内 `tests` 的 QA 模式子集。
* `test:full` 运行包内 `tests` 的 full 模式断言回归，并显式关闭 coverage。
* 当前不暴露包级 `qa` / `test:fast`，避免根目录 QA 递归 workspace 时与既有 root PowerShell QA 重复执行。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* 修改 `psutils/modules`、`psutils/src` 或 `psutils/tests` 时至少运行根目录 PowerShell QA，或按需运行 `pnpm --filter psutils test:qa`。
* 修改 coverage 规则、Pester 配置或跨平台测试策略时，回到根目录执行完整 PowerShell 测试规则。
* 修改 nested module 依赖时，至少用“单独导入消费模块后调用其公共函数”的测试覆盖，防止聚合 manifest 掩盖兄弟模块命令不可见问题。
* 修改模块入口或公共导出时，至少运行 `psutils/tests/moduleContract.Tests.ps1`，并确认仓库生产脚本和示例不再导入 `index.psm1`。
* 修改 README、`docs`、`examples` 或活动 demo 时，运行 `psutils/tests/documentation.Tests.ps1`，确认 manifest 事实、脚本 AST、字面量导入路径和无副作用 smoke 示例一致。

## Guidelines

| Guide | Description | Status |
|-------|-------------|--------|
| [Module Entry Contract](./module-entry-contract.md) | 规范 manifest、PowerShell 版本、兼容 shim、导出一致性与入口测试 | Active |
| [Shared Config Resolver](./shared-config-resolver.md) | `psutils/src/config` 配置来源、合并优先级、导出函数与测试契约 | Active |
| [WSL Docker Wrapper](./wsl-docker-wrapper.md) | `psutils/modules/docker.psm1` WSL Docker wrapper 的路径转换与跨平台测试契约 | Active |
