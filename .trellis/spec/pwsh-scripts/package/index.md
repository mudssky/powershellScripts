# PowerShell Scripts Package Guidelines

> 适用于 `scripts/pwsh` 下的独立 PowerShell 脚本、DevOps 包装入口与跨平台脚本工具。

## Scope

* 包路径：`scripts/pwsh`
* Workspace 包名：`pwsh-scripts`
* 主要入口：`scripts/pwsh/package.json`

## Pre-Development Checklist

* 优先复用根目录已有 PowerShell 脚本入口，例如 `format:pwsh`、`test:pwsh:qa`、`test:pwsh:full:assertions`。
* 不要在包级脚本中重写 Pester 环境变量拼装逻辑；需要指定模式或路径时复用 `scripts/pwsh/devops/Invoke-PesterMode.ps1`。
* 新增或修改脚本配置加载时，先阅读 [Config Loading](./config-loading.md)，优先复用 `psutils/src/config` 通过 `psutils/modules/config.psm1` 暴露的解析器。
* 修改 `scripts/pwsh/misc/package-sources/**` 或 `Switch-Mirrors.ps1` 时，先阅读 [Package Source Transactions](../../infra/package-sources.md)。
* 改动涉及 `profile` 或 `psutils` 时确认是否应归入对应包，不要把所有 PowerShell 规则塞进 `scripts/pwsh`。

## Package Script Contract

* `format` 复用根目录 `format:pwsh`。
* `test:qa` 复用根目录 `test:pwsh:qa`。
* `test:full` 复用根目录 `test:pwsh:full:assertions`，不启用 Linux Docker coverage。
* 当前不暴露包级 `qa` / `test:fast`，避免根目录 QA 递归 workspace 时与既有 root PowerShell QA 重复执行。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* 修改 PowerShell 脚本逻辑时至少运行根目录 `qa:pwsh`，或按需运行 `pnpm --filter pwsh-scripts test:qa`。
* 若改动影响 Pester 配置、coverage 规则或 Linux 容器测试，仍需遵循根目录 `pnpm test:pwsh:all` / coverage 规则。

## Guidelines

| Guide | Description | Status |
|-------|-------------|--------|
| [Config Loading](./config-loading.md) | 独立 PowerShell 脚本加载 env、JSON、`.psd1`、Markdown preset 与 CLI 覆盖参数的统一约定 | Active |
| [Interactive Terminal Launching](./interactive-terminal-launching.md) | 独立 PowerShell 脚本启动 SSH/WSL/TUI 等交互式原生命令时的当前 tab、detached terminal 与 TTY 约定 | Active |
