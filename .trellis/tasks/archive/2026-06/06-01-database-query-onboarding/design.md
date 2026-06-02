# database-query 开箱即用体验设计

## Architecture

本次仍保持 `database-query` 为单文件分发的 TypeScript CLI。改动集中在：

- `src/config.ts`：目标数据库解析放宽，允许 `defaultDatabase` 或显式 `--database` 在无 `databases[]` 时直接成为数据库目标。
- `src/cli.ts`：新增 `init-config` 子命令，生成最小配置模板；增强 `doctor` 文案。
- `scripts/database-query.js`：由构建产物同步。

## Database Target Contract

数据库解析顺序：

1. 显式 `--database`。
2. `instances[].defaultDatabase`。
3. `databases[]` 单候选。
4. 多候选或无候选时按场景报错。

当 `databases[]` 为空但存在显式数据库名或默认数据库名时，返回一个只含 `name` 的 `DatabaseEntry`。这保留 `ResolvedTarget.database?.name` 合同，也不要求上下文伪造完整候选列表。

## Init Config Contract

新增命令：

```bash
node scripts/database-query.js init-config --global [--print] [--force]
node scripts/database-query.js init-config --path <path> [--print] [--force]
```

- `--global` 写入 XDG 全局目录下 `database-query.local.json`。
- `--path` 写入显式路径。
- `--print` 只输出模板，不写文件。
- 默认不覆盖已有文件；`--force` 才允许覆盖。
- 模板使用 `${env:...}` 占位符，不包含真实密码。

## Doctor Contract

`doctor` 仍只检查工具并输出参考安装提示。它不安装底层 CLI。agent 需要根据当前操作系统、权限、PATH、Homebrew keg-only 状态、Docker/WSL 等环境自行选择安装方法。

