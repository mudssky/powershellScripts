# Node Script 包规范

> 适用于 `scripts/node` 下的 Node.js/TypeScript CLI 工具。该包不是前端应用，
> 不使用组件、Hook 或状态管理层。

## 范围

- 包路径：`scripts/node`
- workspace 包名：`node-script`
- 运行时：Node.js，TypeScript 严格模式
- 当前主要工具：`scripts/node/src/rule-loader/`
- 构建入口：`scripts/node/rspack.config.ts`
- 命令包装器：`scripts/node/generate-bin.ts`

不要把根目录 `scripts/*.mjs`、`scripts/bash/` 或 `projects/clis/*` 的约定
直接套用到本包；它们有独立的运行器、构建和测试边界。

## 预开发清单

根据改动类型读取以下文档：

| 改动 | 必读规范 |
| --- | --- |
| 新增脚本、入口或调整目录 | [架构与构建](./architecture-and-build.md) |
| 修改 CLI、加载器、格式化器、转换器或安装器 | [模块契约](./module-contracts.md) |
| 修改公共类型、默认值、错误处理 | [类型与错误处理](./type-and-error-handling.md) |
| 修改行为或测试 | [测试与质量](./testing-and-quality.md) |
| 需要参考本仓库写法 | [代码示例](./code-examples.md) |

开始前还应搜索相关命令名、选项名、输出字段和配置键，确认源码、测试、文档与
构建入口是否都要同步。

## 包脚本契约

- `pnpm --filter node-script typecheck:fast`：只做 TypeScript 类型检查。
- `pnpm --filter node-script check`：执行 Biome 检查。
- `pnpm --filter node-script test:fast`：执行包内 Vitest 测试。
- `pnpm --filter node-script qa`：按类型检查、Biome、Vitest 的顺序执行。
- `pnpm --filter node-script build`：清理 `dist/`、Rspack 打包并生成根目录
  `bin/` 命令包装器。

提交前仍以根目录 `pnpm qa` 为项目级门禁。
