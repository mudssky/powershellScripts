# 按官方方式整理 Hermes 安装目录

## Goal

按 Hermes Agent 官方安装布局修复本机 Hermes 启动方式：程序本体由官方 installer 管理，用户配置与状态通过 `HERMES_HOME` 指向仓库内 `ai/agents/hermes`，避免手动搬迁 `hermes-agent/venv` 导致启动脚本和 editable install 路径失效。

## Requirements

- 保留当前 Hermes 用户配置的关键文件：`config.yaml`、`.env`、`SOUL.md`。
- 在不丢失可恢复资料的前提下备份当前 `ai/agents/hermes` 与 `~/.hermes` 中的 Hermes 状态。
- 按官方 git installer 路径重新安装 Hermes 程序本体，使 `~/.local/bin/hermes`、`~/.hermes/hermes-agent/venv` 等入口由 installer 生成。
- 使用 `HERMES_HOME=/Users/mudssky/projects/powershellScripts/ai/agents/hermes` 指定仓库内配置/状态目录。
- 仓库内 `ai/agents/hermes` 不保存 Hermes 程序源码目录 `hermes-agent/` 和可再生成运行缓存。
- 按推荐范围恢复用户状态：`auth.json`、`skills/`、`cron/`、`hooks/`。
- 不恢复旧 venv 或旧源码安装目录。

## Acceptance Criteria

- [x] `hermes --help` 可以正常运行，不再引用已搬走的 `/Users/mudssky/.hermes/hermes-agent/venv/bin/hermes`。
- [x] `hermes dump` 显示 Hermes 版本信息，且 `hermes_home` 指向 `~/projects/powershellScripts/ai/agents/hermes`。
- [x] `~/.local/bin/hermes` 不再是临时手写的失配入口，或其行为与官方安装入口兼容。
- [x] `ai/agents/hermes/hermes-agent/` 不再作为仓库内长期保存的程序本体。
- [x] 关键配置 `config.yaml`、`.env`、`SOUL.md` 仍存在并能被 Hermes 读取。
- [x] 推荐保留状态 `auth.json`、`skills/`、`cron/`、`hooks/` 在清理后仍可用或已从备份恢复。

## Notes

- 官方文档确认 per-user git installer 的代码目录为 `~/.hermes/hermes-agent/`，命令入口为 `~/.local/bin/hermes`，默认数据目录为 `~/.hermes/`。
- 官方文档确认 `HERMES_HOME` 用于覆盖 Hermes 配置目录，并影响 gateway PID 与 systemd service name，允许多个安装并行。
- 官方备份说明排除 `hermes-agent` 代码目录，说明它不是用户数据备份的一部分。
- 实施后发现 `config.yaml` 含内联 API key，因此 `ai/agents/hermes/.gitignore` 需要忽略本地配置、密钥、认证、数据库、日志、skills、cron 与 hooks。
