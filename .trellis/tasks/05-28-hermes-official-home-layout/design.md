# 按官方方式整理 Hermes 安装目录设计

## Architecture

Hermes 分为两类路径：

- 程序安装路径：由官方 installer 管理，per-user git installer 默认放在 `~/.hermes/hermes-agent/`，并创建 `~/.local/bin/hermes` 入口。
- 用户配置/状态路径：由 `HERMES_HOME` 管理，默认是 `~/.hermes/`，本任务指定为 `/Users/mudssky/projects/powershellScripts/ai/agents/hermes`。

当前问题来自把 `~/.hermes/hermes-agent` 搬入仓库后，`~/.local/bin/hermes` 和 venv entrypoint 仍硬编码旧路径。正确处理方式不是修补 venv，而是重新生成官方安装入口，并只把用户配置/状态目录指向仓库位置。

## Data Boundaries

长期保留：

- `config.yaml`：模型、provider、toolsets、gateway 等配置。
- `.env`：密钥和环境变量。
- `SOUL.md`：agent 个性与身份。

按需保留：

- `auth.json`：OAuth 或 provider 认证状态。
- `skills/`：已安装或用户创建技能。
- `cron/`、`hooks/`：任务和钩子。

可再生成：

- `logs/`、`audio_cache/`、`image_cache/`、`models_dev_cache.json`。
- `state.db*`、`kanban.db`、`gateway_state.json`、`channel_directory.json`。
- `sessions/`、`memories/`、`sandboxes/`，但删除会丢历史会话、记忆或沙箱。
- `hermes-agent/` 程序源码与 venv。

## Compatibility

- 对用户的 `hermes` 命令保持不变，仍走 `~/.local/bin/hermes`。
- 通过 shell 环境持久化 `HERMES_HOME`，让官方入口读取仓库内配置。
- 如果用户已有 `~/.hermes` 中的新初始化数据，先备份再覆盖关键配置。

## Rollback

- 清理或重装前创建时间戳备份目录。
- 如果官方重装失败，保留当前临时 wrapper 和现有仓库内 Hermes 数据，不删除备份。
- 若 `HERMES_HOME` 设置导致异常，可临时取消该环境变量回到官方默认 `~/.hermes`。
