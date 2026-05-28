# Hermes 本地嵌套仓库方案 PRD

## Goal

把 `ai/agents/hermes` 从“主仓库只提交 README 与 `.gitignore` 的运行时目录”调整为“主仓库记录边界，Hermes 目录自己作为本地私有 git 仓库管理”的方案。

用户价值：

- Hermes 的个人配置、密钥、技能、cron、SOUL 等内容可以有本地历史。
- 这些内容默认不进入 `powershellScripts` 主仓库，也不会被推送到外部远端。
- 后续维护者能清楚区分主仓库约定与 Hermes 私人状态仓库。

## Confirmed Facts

- 已有主仓库提交记录了 Hermes 官方安装目录与 `HERMES_HOME` 分离：
  - Hermes 程序本体：`~/.hermes/hermes-agent`
  - Hermes 运行态 home：`ai/agents/hermes`
- 当前 `ai/agents/hermes/README.md` 写的是本目录默认只提交 `README.md` 与 `.gitignore`。
- 当前 `ai/agents/hermes/.gitignore` 忽略了 `config.yaml`、`.env`、`SOUL.md`、`auth.json`、状态数据库、日志、`skills/`、`cron/` 等 Hermes 本地内容。
- `.trellis/spec/infra/hermes-agent-layout.md` 当前约定：
  - `ai/agents/hermes` 是 `HERMES_HOME`
  - 真实 `config.yaml` 可能含密钥，不应提交到主仓库
  - `$HERMES_HOME/skills/` 不建议作为主仓库可提交技能源目录
- 用户认为如果主仓库只提交 ignore/README，Hermes 目录放进主仓库的 git 管理意义很低。
- 用户偏好：Hermes 私有本地仓库可以记录密钥；数据库、日志、缓存、会话等运行时产物仍然需要忽略。

## Requirements

- 主仓库必须继续避免提交 Hermes 的真实配置、密钥、认证状态、数据库、日志、会话、记忆和官方 bundled skills 产物。
- `ai/agents/hermes` 可以作为独立本地 git 仓库，用于记录私人 Hermes 配置、密钥、技能与 cron 历史。
- Hermes 私有仓库内部应提交可读、可恢复的个人配置，例如：
  - `config.yaml`
  - `.env`
  - `SOUL.md`
  - 用户自定义 `skills/`
  - 用户自定义 `cron/`
- Hermes 私有仓库内部仍应忽略运行时产物，例如：
  - `state.db*`
  - `kanban.db*`
  - `logs/`
  - `sessions/`
  - `memories/`
  - cache、pid、lock、临时文件
- 主仓库文档需要清楚说明嵌套本地 git 仓库的目的、边界、初始化方式和不 push 的约定。
- 主仓库需要避免误把嵌套仓库当作 submodule 或普通目录提交。
- 如果修改主仓库规范，需要同步更新 Hermes README 和 Trellis infra spec。

## Acceptance Criteria

- PRD 明确记录采用本地嵌套 git 仓库策略。
- 主仓库 README/spec 说明：
  - `ai/agents/hermes` 是 `HERMES_HOME`
  - 它也可以是本机私有 git 仓库
  - 主仓库不接管其中的真实配置与运行状态
  - 私有仓库默认不配置 remote，不 push 到外部
- 主仓库 git 状态不会把 Hermes 私有内容暴露为待提交文件。
- Hermes 私有仓库的 `.gitignore` 允许配置、密钥、用户技能和 cron 入库，同时忽略数据库、日志、缓存、会话、记忆和临时文件。
- 如实施初始化，`ai/agents/hermes/.git` 存在，且该仓库能独立 `git status`。
- 立即初始化 `ai/agents/hermes` 为本地私有 git 仓库，并创建第一版本地提交。

## Out of Scope

- 不把 Hermes 私人仓库推送到 GitHub/Gitee 等远端。
- 不迁移 Hermes 程序安装目录；继续遵循官方 `~/.hermes/hermes-agent` 布局。
- 不修改 LiteLLM gateway 模型配置。
- 不清理或重写现有密钥历史；本任务只建立新的管理边界。

## Open Questions

- 无。
