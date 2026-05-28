# Hermes Agent 本地目录

这个目录作为本机 Hermes 的 `HERMES_HOME` 使用，只保存运行时配置与状态。Hermes 程序本体不要放在这里，按官方布局安装在：

```text
~/.hermes/hermes-agent/
```

本机环境变量放在被忽略的私有片段里：

```bash
# shell/shared.d/env.local.sh
export HERMES_HOME="$HOME/projects/powershellScripts/ai/agents/hermes"
```

`shell/deploy.sh --shell zsh` 会把它同步到 `~/.bashrc.d/env.local.sh`，再由 `macos/config/.zshrc` 加载。

## Git 边界

本目录下默认只提交：

```text
README.md
.gitignore
```

以下内容都是本机状态，不提交：

```text
config.yaml
.env
SOUL.md
auth.json
state.db*
kanban.db*
logs/
sessions/
memories/
skills/
cron/
hooks/
hermes-agent/
```

原因：`config.yaml` 和 `.env` 可能含密钥；`auth.json`、数据库、日志、会话、记忆和技能目录包含认证状态或个人上下文；`skills/` 还会混入官方 bundled skills、Hub 状态和 agent 自动创建的内容。

## 个人技能放哪里

Hermes 运行时会从 `$HERMES_HOME/skills/` 读取技能，但这个目录不进 git。要版本管理自己的技能，放在仓库的技能区：

```text
ai/skills/private/hermes/<skill-name>/SKILL.md
```

开发中或可共享的技能可以放：

```text
ai/skills/dev/<skill-name>/SKILL.md
```

需要给 Hermes 使用时，再复制或软链到运行时目录：

```bash
mkdir -p "$HERMES_HOME/skills/private"
ln -s "$PWD/ai/skills/private/hermes/<skill-name>" "$HERMES_HOME/skills/private/<skill-name>"
```

如果技能只想留在 Hermes 本地、不要版本管理，也可以直接放在：

```text
$HERMES_HOME/skills/<category>/<skill-name>/SKILL.md
```

这类技能会被 `.gitignore` 忽略。

## 验证

```bash
hermes version
hermes dump
hermes gateway status
git status --short -uall -- ai/agents/hermes
```
