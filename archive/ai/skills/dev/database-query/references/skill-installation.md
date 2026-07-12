# Agent Skill 手动安装指南

## 使用场景

自动安装应优先使用仓库的 `ai/skills/Install-Skills.ps1`，这类情况不需要读本文。

本文只用于无法运行自动安装脚本、需要手动复制到某个 agent skill 目录，或需要排查手动安装结果的场景。

## 手动安装内容

最小运行态需要复制这些内容：

```text
database-query/
  SKILL.md
  scripts/
    database-query.js
  references/
  examples/
```

开发态文件可以不复制：

```text
package.json
tsconfig.json
src/
tests/
build.mjs
node_modules/
```

`scripts/database-query.js` 是已构建的单文件入口，不需要在安装目录运行 `pnpm install` 或 `pnpm build`。

## 手动复制

从仓库复制目录：

```powershell
Copy-Item -Recurse -Force `
  .\ai\skills\dev\database-query `
  <agent-skills-dir>\database-query
```

如果只想复制运行态文件，应确保 `SKILL.md`、`scripts/`、`references/`、`examples/` 都存在。

## 手动软链接

开发机上可以用目录链接减少重复复制。Windows 示例：

```powershell
New-Item -ItemType Junction `
  -Path <agent-skills-dir>\database-query `
  -Target .\ai\skills\dev\database-query
```

Linux/macOS 示例：

```bash
ln -s "$(pwd)/ai/skills/dev/database-query" "<agent-skills-dir>/database-query"
```

软链接适合本机开发，不适合作为跨机器分发方式。

## 手动安装后验证

进入手动安装后的 `database-query` 目录执行：

```bash
node scripts/database-query.js --help
node scripts/database-query.js doctor
node scripts/database-query.js config paths
node scripts/database-query.js config current
node scripts/database-query.js check-sql --dialect postgres --level readonly --sql "select 1 limit 1"
```

如果这些命令可运行，说明 skill 的脚本入口可用。底层数据库客户端缺失时，`doctor` 会输出安装提示；在 WSL 中，如果 PATH 里有 Windows `.exe` 客户端，`doctor` 会标记为 `ok (windows-exe)`。`exec` 与 `client --print-command` 使用同一客户端解析规则，优先原生命令，缺失时才使用 `.exe`。

## 配置文件位置

`database-query.js` 未传 `--config` 时先从当前工作目录查找项目级配置；找不到时再查找 agent 无关的用户级全局配置目录：

```text
$XDG_CONFIG_HOME/database-query/
~/.config/database-query/   # XDG_CONFIG_HOME 未设置时
```

每个目录内按以下默认文件名顺序查找：

```text
database-query.local.mjs
database-query.local.js
database-query.local.json
database-query.config.mjs
database-query.config.js
database-query.config.json
```

手动安装 skill 不代表要把数据库配置放进 skill 目录。项目专用配置通常放在当前项目根目录；跨 agent/跨项目复用的本机私有配置放在用户级全局目录；临时或特殊配置通过 `--config` 显式指定：

```bash
node scripts/database-query.js context --config ./database-query.local.json --format json
```

显式 `--config` 永远优先于默认查找。真实项目级 `database-query.local.*` 必须被所在项目的 `.gitignore` 忽略；全局 `database-query.local.*` 应限制为当前用户可读写。

生成最小用户级全局配置：

```bash
node scripts/database-query.js config paths
node scripts/database-query.js config current
node scripts/database-query.js config current --format json
node scripts/database-query.js init-config --global
node scripts/database-query.js init-config --global --print
```

`init-config` 默认写入 `database-query.local.json`，使用 `${env:...}` 占位符，不包含真实密码，也不会覆盖已有文件；需要覆盖时显式传 `--force`。

## 常见问题

- agent 找不到 skill：确认目标 agent 的 skill 目录名称是 `database-query`，且目录下有 `SKILL.md`。
- 脚本无法运行：确认安装目录下存在 `scripts/database-query.js`，并且本机可运行 `node`。
- `context` 找不到配置：切换到项目根目录运行，或传 `--config`。
- `doctor` 提示缺少底层客户端：查看 `client-installation.md`。
- 手动复制后行为仍是旧版本：重新复制 `SKILL.md`、`scripts/`、`references/`，或改用软链接。
