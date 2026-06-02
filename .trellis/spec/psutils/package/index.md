# PsUtils Package Guidelines

> 适用于 `psutils` PowerShell 模块、模块源码、示例、文档和模块内 Pester 测试。

## Scope

* 包路径：`psutils`
* Workspace 包名：`psutils`
* 主要入口：`psutils/package.json`

## Pre-Development Checklist

* 模块源码应优先放在 `psutils/modules` 或既有 `psutils/src` 结构中，不要从根目录新增平行模块目录。
* 修改配置解析、env 读取、frontmatter、`.psd1` data file 或 CLI 参数合并时，先阅读 [Shared Config Resolver](./shared-config-resolver.md)。
* Pester 运行方式复用 `scripts/pwsh/devops/Invoke-PesterMode.ps1`，包内脚本通过 `PWSH_TEST_PATH` 限定 `./tests`。
* 覆盖率门槛仍由根目录 `PesterConfiguration.ps1` 统一管理；包级 `test:full` 只做断言回归，不单独改 coverage 策略。

## Package Script Contract

* `test:qa` 运行包内 `tests` 的 QA 模式子集。
* `test:full` 运行包内 `tests` 的 full 模式断言回归，并显式关闭 coverage。
* 当前不暴露包级 `qa` / `test:fast`，避免根目录 QA 递归 workspace 时与既有 root PowerShell QA 重复执行。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* 修改 `psutils/modules`、`psutils/src` 或 `psutils/tests` 时至少运行根目录 PowerShell QA，或按需运行 `pnpm --filter psutils test:qa`。
* 修改 coverage 规则、Pester 配置或跨平台测试策略时，回到根目录执行完整 PowerShell 测试规则。

## Guidelines

| Guide | Description | Status |
|-------|-------------|--------|
| [Shared Config Resolver](./shared-config-resolver.md) | `psutils/src/config` 配置来源、合并优先级、导出函数与测试契约 | Active |
