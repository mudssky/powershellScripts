# Bash Scripts Package Guidelines

> 适用于 `scripts/bash` 下的 Bash 脚本、构建辅助脚本与 Vitest 包装测试。

## Scope

* 包路径：`scripts/bash`
* Workspace 包名：`bash-scripts`
* 主要入口：`scripts/bash/package.json`

## Pre-Development Checklist

* 确认改动是否属于 Bash 脚本域；如果只修改 Linux 发行版安装脚本，应优先检查 `linux/*` 目录规范，而不是归入本包。
* 复用现有 `vitest.config.ts` 与 `systemd-service-manager/vitest.config.ts`，不要为同一测试集合新增平行配置。
* 修改 package source Stage 0 helper 时，先阅读 [Package Source Transactions](../../infra/package-sources.md)。
* 新增包级脚本时保持与根目录 `package.json` 的 QA 语义一致，避免根入口和包入口覆盖范围不同。

## Package Script Contract

* `test:bash` 复用根目录 `test:bash`，运行 `scripts/bash/vitest.config.ts` 覆盖的 Bash 构建测试。
* `test:systemd-service-manager` 运行 systemd 子项目测试。
* 当前不暴露包级 `qa` / `test:fast`，避免根目录 QA 递归 workspace 时与既有 root Bash QA 重复执行。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* Bash 业务逻辑或测试逻辑改动时，运行根目录 Bash QA，或按需运行 `pnpm --filter bash-scripts test:bash` 与 `pnpm --filter bash-scripts test:systemd-service-manager`。
* 不要把 `linux/fnos` 或其他 Linux 子项目测试混入本包；它们应在后续独立包边界中处理。
