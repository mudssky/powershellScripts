# 按官方方式整理 Hermes 安装目录实施计划

## Checklist

1. 停止 Hermes gateway 或确认当前未运行，避免状态文件写入中途迁移。
2. 创建时间戳备份，至少包含：
   - `ai/agents/hermes/config.yaml`
   - `ai/agents/hermes/.env`
   - `ai/agents/hermes/SOUL.md`
   - `ai/agents/hermes/auth.json`
   - `ai/agents/hermes/skills/`
   - `ai/agents/hermes/cron/`
   - `ai/agents/hermes/hooks/`
   - 当前 `~/.local/bin/hermes`
   - 当前 `~/.hermes`
3. 移除或隔离仓库内 `ai/agents/hermes/hermes-agent/`，避免继续使用搬迁后的 venv。
4. 按官方 installer 重新安装 Hermes，让 installer 生成 `~/.hermes/hermes-agent/` 和 `~/.local/bin/hermes`。
5. 配置 shell 环境变量：
   - `HERMES_HOME=/Users/mudssky/projects/powershellScripts/ai/agents/hermes`
6. 确保 `ai/agents/hermes` 至少保留 `config.yaml`、`.env`、`SOUL.md`，按需恢复 `auth.json`、`skills/`、`cron/`、`hooks/`。
7. 运行验证命令：
   - `hermes --help`
   - `hermes version`
   - `hermes dump`
8. 检查 `hermes dump` 的 `hermes_home` 是否指向仓库内路径。
9. 检查 `git status --short -uall -- ai/agents/hermes`，确认 `.gitignore` 没有误漏密钥和运行状态。

## Validation

- `hermes --help` 正常输出 CLI 帮助。
- `hermes version` 正常输出版本。
- `hermes dump` 显示 `hermes_home: ~/projects/powershellScripts/ai/agents/hermes`。
- `git check-ignore` 命中 `.env`、日志、数据库和 `hermes-agent/`。

## Risky Files

- `/Users/mudssky/.local/bin/hermes`
- `/Users/mudssky/.hermes`
- `/Users/mudssky/projects/powershellScripts/ai/agents/hermes`
- 用户 shell rc 文件，如 `~/.zshrc`

## Rollback

- 使用备份恢复 `~/.local/bin/hermes`。
- 使用备份恢复 `~/.hermes`。
- 从备份恢复仓库内 `ai/agents/hermes` 的关键配置。
- 临时移除 `HERMES_HOME` 环境变量，回到官方默认 home。
