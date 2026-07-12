# JSON Diff Tool Package Guidelines

> 适用于 `projects/clis/json-diff-tool` 的 TypeScript CLI。

## Scope

* 包路径：`projects/clis/json-diff-tool`
* Workspace 包名：`json-diff-tool`
* 主要入口：`projects/clis/json-diff-tool/package.json`

## Pre-Development Checklist

* 复用包内已有 `typecheck:fast`、`check`、`test:fast`、`qa` 脚本契约。
* CLI 行为变更应同步检查 `commander` 命令参数、类型检查和 Vitest 覆盖。
* 不要把根目录 `scripts/node` 的通用脚本规则混入本包；这是独立 CLI 项目。

## Package Script Contract

* `qa` 必须保持为类型检查、Biome 检查和快速测试的组合。
* `test:fast` 与 `test` 应保持等价或更快的本地反馈语义。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* CLI 逻辑改动时运行 `pnpm --filter json-diff-tool qa`。
