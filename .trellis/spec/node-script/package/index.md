# Node Script Package Guidelines

> 适用于 `scripts/node` 下的 Node/TypeScript 脚本工具。

## Scope

* 包路径：`scripts/node`
* Workspace 包名：`node-script`
* 主要入口：`scripts/node/package.json`

## Pre-Development Checklist

* 优先复用包内 `typecheck:fast`、`check`、`test:fast`、`qa` 脚本。
* CLI 或构建行为变更应同时检查 `generate-bin.ts`、Rspack 配置和 Vitest 覆盖。
* 不要把 `projects/clis/*` 的独立 CLI 规则混入本包。

## Package Script Contract

* `qa` 保持类型检查、Biome 检查和快速测试的组合。
* `build` 负责清理 dist、执行 Rspack 并生成 bin 文件。
