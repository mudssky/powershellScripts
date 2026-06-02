# AI Agents

这个目录用于记录本仓库接入的本地 agent 布局约定。

## Hermes

`/Volumes/Data/agents/hermes/` 是本机 Hermes 的 `HERMES_HOME`，同时是独立的本地私有 git 仓库。仓库内的 `ai/agents/hermes/` 仅作为兼容旧路径的符号链接，主仓库通过 `.gitignore` 忽略该路径，避免把真实配置、密钥、认证状态、会话、记忆、日志和数据库提交到 `powershellScripts`。

Hermes 程序本体继续按官方布局安装在：

```text
~/.hermes/hermes-agent/
```

本机环境变量放在私有环境片段中：

```bash
export HERMES_HOME="/Volumes/Data/agents/hermes"
```

Hermes 私有仓库可以提交 `config.yaml`、`.env`、`SOUL.md`、个人 `skills/` 和 `cron/`；继续忽略 `auth.json`、`state.db*`、`kanban.db*`、`logs/`、`sessions/`、`memories/`、缓存、lock、pid 和临时文件。该私有仓库默认不配置 remote，不 push 到外部。
