# Claude Code 多 key 切换工具实现计划

## Checklist

- [x] 阅读 `shell/shared.d/ai.sh`、`shell/deploy.sh` 与相关规范，确认函数风格和加载时机。
- [x] 新增 `shell/shared.d/claude-profile.sh`，承载 Bash/Zsh 版 `claude-profile` 入口与 `use/run/current/list/add` 子命令。
- [x] `claude-profile run` 读取 profile env 后直接启动 `claude "$@"`，不写项目 settings。
- [x] `claude-profile run` 调用 `claude` 时通过会话级覆盖让 profile env 优先生效，同时不破坏 user/project/local 的其他配置。
- [x] `claude-profile add` 创建 profile 模板，并优先通过 `$VISUAL` / `$EDITOR` 打开。
- [x] 使用 `jq` 合并 profile 与 `.claude/settings.local.json`；如缺失则给出明确安装提示。
- [x] 写入时创建 `.claude/`，通过临时文件 + rename 降低 settings 损坏风险。
- [x] 输出时对 API key 脱敏。
- [x] 更新相关文档或注释，说明 profile 文件示例与 VS Code Reload Window 使用方式。
- [x] 添加 profile 模板创建与编辑器打开的验证场景。
- [x] 确认 `shell/deploy.sh` 可继续加载新文件而无需特殊逻辑。
- [x] 添加 `run` 在存在 `~/.claude/settings.json` 且包含 env 时仍能让 profile 覆盖同名键的验证场景。
- [x] 运行根目录 `pnpm qa`。

## Validation Commands

```bash
pnpm qa
```

手工验证建议：

```bash
tmpdir=$(mktemp -d)
cd "$tmpdir"
mkdir -p ~/.claude/profiles
claude-profile use glm
claude-profile current
cat .claude/settings.local.json
claude-profile run glm --version
claude-profile run official --version
```

## Risky Files

- `shell/shared.d/ai.sh`：会被 Bash/Zsh 交互 shell source，语法错误会影响 shell 启动体验。
- `shell/shared.d/claude-profile.sh`：会被 Bash/Zsh 交互 shell source，语法错误会影响 shell 启动体验。
- 项目 `.claude/settings.local.json`：可能包含 secrets，工具输出和测试说明不得泄露真实 key。

## Review Gate Before Start

已确认：主入口采用 `claude-profile use/run/current/list/add` 子命令风格。
`add` 作为创建入口会生成模板并立即打开编辑器。
首版只做 Bash/Zsh 版本；PowerShell / 桌面账号级切换不做。
