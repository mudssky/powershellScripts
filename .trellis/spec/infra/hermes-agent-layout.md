# Hermes Agent Layout Spec

> 本规范记录 Hermes Agent 在本仓库中的本地安装、`HERMES_HOME` 与 git 提交边界。

---

## Scenario: Hermes 程序目录与 HERMES_HOME 分离

### 1. Scope / Trigger

- Trigger: 安装、迁移、修复或升级 Hermes Agent；修改 `ai/agents/hermes/**`、`macos/config/.zshrc` 中的 Hermes 环境变量；处理 Hermes gateway launchd 服务。
- Scope: 程序本体由官方安装目录管理，用户配置和本地状态通过 `HERMES_HOME` 指向仓库内 `ai/agents/hermes`。
- Design intent: 允许本地 Hermes 配置靠近仓库，同时避免把 venv、上游源码、密钥和运行状态提交进当前仓库。

### 2. Signatures

- 官方默认安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

- 推荐本机布局：

```text
~/.hermes/hermes-agent/                         # Hermes 程序本体、git checkout、venv
~/.local/bin/hermes -> ~/.hermes/hermes-agent/venv/bin/hermes
ai/agents/hermes/                               # HERMES_HOME，本地配置和运行状态
```

- 环境变量：

```bash
export HERMES_HOME="/Users/mudssky/projects/powershellScripts/ai/agents/hermes"
```

- 本机私有环境片段：

```bash
# shell/shared.d/env.local.sh，由 shell/deploy.sh 同步到 ~/.bashrc.d/env.local.sh
export HERMES_HOME="$HOME/projects/powershellScripts/ai/agents/hermes"
```

### 3. Contracts

- `HERMES_HOME` 只表示 Hermes 配置和状态目录，不是程序安装目录。
- 不要把 `hermes-agent/` 上游源码或 `venv/` 放进 `ai/agents/hermes`；这些路径含绝对 shebang、editable install finder 和依赖缓存，移动后容易失效。
- `~/.local/bin/hermes` 应由官方 installer 或 `setup-hermes.sh` 生成，指向 `~/.hermes/hermes-agent/venv/bin/hermes`。
- `ai/agents/hermes/README.md` 与 `.gitignore` 可以提交；`config.yaml`、`.env`、`SOUL.md`、`auth.json`、`state.db*`、`kanban.db*`、`logs/`、`skills/`、`cron/`、`hooks/` 均视为本机状态，默认不得提交。
- `config.yaml` 可能包含内联 `api_key`，不能因为文件名像配置就纳入版本控制。
- 修复 gateway 后，launchd plist 必须显式包含 `HERMES_HOME`，`ProgramArguments` 指向官方程序目录下的 venv python，日志路径指向 `HERMES_HOME/logs/`。
- 本机专属 `HERMES_HOME` 优先放在被忽略的 `shell/shared.d/env.local.sh`，再通过 `shell/deploy.sh --shell zsh` 同步到 `~/.bashrc.d/env.local.sh`；不要把个人绝对路径写进可提交的 `macos/config/.zshrc`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `~/.local/bin/hermes` 指向已搬走的 `~/.hermes/hermes-agent/venv/bin/hermes` | `hermes` 报 no such file；需重建官方安装入口 |
| `HERMES_HOME` 指向仓库且未显式分离程序目录 | 官方 installer 可能把程序装进 `$HERMES_HOME/hermes-agent`，应避免长期保留 |
| `hermes dump` | `Project` 应为 `~/.hermes/hermes-agent`，`hermes_home` 应为 `~/projects/powershellScripts/ai/agents/hermes` |
| `hermes gateway status` | Service definition matches current install；launchd 环境含 `HERMES_HOME` |
| `git status --short -uall -- ai/agents/hermes` | 只应看到 `.gitignore` 等安全文件，不应出现密钥、数据库、日志、skills 产物 |

### 5. Good/Base/Bad Cases

- Good: 程序安装在 `~/.hermes/hermes-agent`，`HERMES_HOME` 指向 `ai/agents/hermes`，`ai/agents/hermes/.gitignore` 忽略本地配置、密钥和状态。
- Good: 需要版本管理的个人 Hermes skill 源文件放在 `ai/skills/private/hermes/<skill-name>/SKILL.md` 或 `ai/skills/dev/<skill-name>/SKILL.md`，再复制或软链到 `$HERMES_HOME/skills/`。
- Good: 网络 clone 失败时，使用已有官方 checkout 回到 `~/.hermes/hermes-agent` 后运行 `./setup-hermes.sh` 重建 venv 和入口。
- Base: 完全使用官方默认安装，程序和默认数据都在 `~/.hermes`；适合不需要仓库内状态目录的场景。
- Bad: 把 `~/.hermes/hermes-agent` 直接搬到 `ai/agents/hermes/hermes-agent` 后继续使用旧 venv；entrypoint 和 editable install finder 会保留旧绝对路径。
- Bad: 提交 `config.yaml`、`.env`、`auth.json` 或 `state.db*`；这些文件可能含密钥、OAuth token、会话和个人记忆。
- Bad: 把 `$HERMES_HOME/skills/` 当作可提交的个人技能源目录；它会混入官方 bundled skills、Hub 状态和 agent-created 内容。

### 6. Tests Required

- CLI smoke:

```bash
hermes --help
hermes version
HERMES_HOME=/Users/mudssky/projects/powershellScripts/ai/agents/hermes hermes dump
```

- Shell env:

```bash
zsh -ic 'printf "%s\n" "$HERMES_HOME"'
zsh -lc 'printf "%s\n" "$HERMES_HOME"'
```

- Gateway:

```bash
HERMES_HOME=/Users/mudssky/projects/powershellScripts/ai/agents/hermes hermes gateway status
plutil -p ~/Library/LaunchAgents/ai.hermes.gateway.plist
```

- Git safety:

```bash
git check-ignore -v ai/agents/hermes/config.yaml ai/agents/hermes/.env ai/agents/hermes/state.db ai/agents/hermes/skills/apple/apple-notes/SKILL.md
git status --short -uall -- ai/agents/hermes
```

### 7. Wrong vs Correct

#### Wrong

```text
ai/agents/hermes/hermes-agent/venv/bin/hermes
```

问题：venv entrypoint 和 editable install 元数据包含绝对路径，搬家后容易继续引用旧目录。

#### Correct

```text
~/.hermes/hermes-agent/venv/bin/hermes
ai/agents/hermes/                  # HERMES_HOME only
```

理由：程序安装目录遵循官方布局，仓库目录只承载本机 Hermes home，并由 `.gitignore` 阻止密钥和运行状态入库。
