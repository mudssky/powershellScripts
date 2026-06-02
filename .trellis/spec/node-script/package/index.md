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

## Scenario: database-query Skill CLI Contracts

### 1. Scope / Trigger

* Trigger: 修改 `ai/skills/dev/database-query` 的 CLI 命令签名、配置查找输出或底层客户端诊断输出。

### 2. Signatures

* `database-query config paths [--format text|json]`
* `database-query config current [--config <path>] [--format text|json]`
* `database-query doctor`

### 3. Contracts

* `config paths` 只输出配置查找元信息，不读取配置内容，不输出任何密码、token、URI 或连接串。
* `config current` 只解析“会使用哪个配置文件”。显式 `--config` 优先；未传时按项目目录、用户级全局目录的默认文件名顺序查找。
* `doctor` 对底层客户端先探测原生命令，再在缺失时探测 Windows `.exe` 命令，状态可为 `ok (native)`、`ok (windows-exe)` 或 `missing`。
* `exec` / `client --print-command` 应复用底层客户端探测结果展示和调用命令，优先 native，缺失时使用 `.exe`。

### 4. Validation & Error Matrix

* `config current` 找不到配置 -> stdout 输出 `<not-found>` 与创建提示，stderr 输出错误，退出码为 1。
* `config <unknown>` -> stderr 输出不支持的 action，退出码为 1。
* `doctor` 原生命令和 `.exe` 都不可用 -> 输出 `missing` 和安装提示。
* SQLite SQL 执行只要求 instance 配置 `path`，不要求 database。

### 5. Good/Base/Bad Cases

* Good: WSL 中只有 `psql.exe` 时，`doctor` 输出 `psql: ok (windows-exe)`。
* Base: Linux 中存在 `mysql` 时，`doctor` 输出 `mysql: ok (native)`。
* Bad: 为了打印配置位置调用 `init-config --global`，可能误创建配置文件；应使用 `config paths/current`。

### 6. Tests Required

* CLI 测试必须覆盖 `config paths`、`config current`、无配置错误路径、`doctor` 的 `.exe` 兜底、执行计划 `.exe` 兜底、SQLite 无 database 执行路径和完全缺失路径。

### 7. Wrong vs Correct

#### Wrong

```bash
node scripts/database-query.js init-config --global
```

#### Correct

```bash
node scripts/database-query.js config paths
node scripts/database-query.js config current
```

## Quality Check

* 配置或文档改动可只做可发现性检查。
* Node 脚本逻辑改动时运行 `pnpm --filter node-script qa`。
