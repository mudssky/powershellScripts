# Claude Code 多 key 切换工具设计

## Architecture and Boundaries

实现入口分为两处：

- `shell/shared.d/claude-profile.sh`：Bash/Zsh 通用 profile 命令集合。
- `shell/shared.d/ai.sh`：保留通知/铃声等轻量 helper。

首版只实现 Bash/Zsh 侧命令，不修改 PowerShell profile。桌面账号级切换由 `ccswitch` 承担。工具包含三类入口：

- 临时启动入口：读取本机 profile，把 env 只注入当前 `claude` 进程，例如 `claude-profile run glm`。
- 项目持久化入口：读取本机 profile，更新当前项目的 Claude Code local settings，例如 `claude-profile use glm`。
- profile 创建入口：创建 `~/.claude/profiles/<name>.json` 模板并打开编辑器，例如 `claude-profile add glm`。

工具不负责管理全局 Claude 配置同步。

本机 profile 目录：

```text
~/.claude/profiles/
├── glm.json
└── official.json
```

项目写入目标：

```text
<project>/.claude/settings.local.json
```

首版不写仓库可提交的 `.claude/settings.json`，避免误提交 secrets。

## Data Flow

### 临时启动

1. 用户在任意目录执行 `claude-profile run glm`。
2. 函数解析 `~/.claude/profiles/glm.json`。
3. 函数把 profile 的 `env` 注入当前 `claude` 子进程。
   - Bash/Zsh：以子进程环境变量方式执行 `claude "$@"`。
4. 函数将剩余参数原样透传给 `claude`，例如 `claude-profile run glm -p "检查状态"`。
5. 函数通过会话级 `--settings <file-or-json>` 覆盖或等价临时注入方式，让 profile 的 `env` 优先生效，同时保留 user/project/local 的其他配置。
6. 函数不写 `.claude/settings.local.json`，因此没有项目目录也能正常使用。

### 项目持久化

1. 用户执行 `claude-profile use glm`。
2. 函数解析 `~/.claude/profiles/glm.json`。
3. 函数创建当前目录下 `.claude/`。
4. 函数读取已有 `.claude/settings.local.json`，若不存在则从空对象开始。
   - Bash/Zsh 使用 `jq` 做 JSON 解析与合并；若缺失，给出明确安装提示。
5. 函数合并 profile 内容：
   - `env` 对象按键覆盖。
   - 额外记录当前 profile 名称，用于 `claude-profile current` 展示。
6. 函数原子写回 `.claude/settings.local.json`。
7. 用户打开 / Reload VS Code 后使用 Claude 插件，或在新 Claude Code 会话中读取项目 settings。

### Profile 创建

1. 用户执行 `claude-profile add glm`。
2. 函数检查 `~/.claude/profiles/glm.json` 是否存在。
3. 若不存在，函数生成最小模板文件，包含 `env` 占位结构与常见注释提示。
4. 函数使用 `$VISUAL` / `$EDITOR` 或平台默认编辑器打开该文件。
5. 用户保存后，profile 可立即被 `run` 或 `use` 使用。

## Contracts

profile JSON 首版合同：

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:34000"
  }
}
```

`claude-profile current` 输出合同：

- 显示当前项目 settings 文件路径。
- 显示当前 profile 名称。
- 显示 `ANTHROPIC_BASE_URL`、模型相关变量。
- API key 只显示是否存在和脱敏尾部，不输出完整值。

快捷命令合同：

- `claude-profile run <profile> [args...]` 是通用入口。
- `claude-profile current` 返回当前项目所选 profile。
- `claude-profile list` 列出 profile 目录。
- `claude-profile add <profile>` 创建模板并打开编辑器。
- 命令不存在或 profile 不存在时，输出可行动的错误提示。

## Compatibility Notes

- Context7 查询到的 Claude Code 文档显示 VS Code 扩展共享 Claude Code settings，用户级 settings 明确共享；项目级 settings 是 Claude Code 的正常配置来源。基于此，项目 `.claude/settings.local.json` 是比 shell export 更兼容 VS Code 插件的主路。
- 官方 settings hierarchy 显示命令行参数优先级高于 local/project/user，因此 `run` 更适合做临时会话覆盖，而不是排除 user settings。
- 现成工具也大多分成三类：`settings.local.json`/`settings.json` 管理器、`~/.claude` 目录级 profile/symlink 切换、以及只负责导出 env/启动 Claude 的 wrapper。
- 如果某个版本的 VS Code 插件不加载项目 local settings，备用方案才考虑 `CLAUDE_CONFIG_DIR` 或全局 symlink 方案，但那会偏向机器全局，不适合作为 per-project 默认。
- `shell/shared.d/ai.sh` 由 `shell/deploy.sh` 分发到 Bash/Zsh loader，函数实现应避免使用只在交互式 Bash 可用的特性。
- `shell/shared.d/claude-profile.sh` 会和 `ai.sh` 一起被 `shell/deploy.sh` 链接到目标目录，文件粒度比继续堆在 `ai.sh` 更清晰。
- 首版不修改 `profile/core/` 或 `profile/profile.ps1`，因此不触发 PowerShell profile 加载风险。
- `cc` 在当前环境里已经是 `/usr/bin/cc`，所以把主入口做成 `cc use` 风格会有明显冲突风险。
- `add` 的编辑器选择优先尊重 `$VISUAL`，其次 `$EDITOR`，再使用平台默认编辑器；若都不可用，需要报出可行动错误。
- `run` 的核心是临时会话级覆盖，不是切换用户 settings 文件本身；这和官方 precedence 一致，也最接近主流工具的实际做法。

## Naming Options

- `claude-profile ...`：更像真正的 CLI 子命令，直观且冲突少，但名字更长。
- `claude profile ...`：最像自然语言风格，不过会更像是在包装现有 `claude` CLI，且需要确认不会与官方命令空间冲突。
- 短别名可作为后续附加入口，但不应成为主入口，以免再次靠近系统 `cc` 命令。
- `add` 的编辑器弹出流程应保持一次命令完成，不需要再手动跑第二个命令。
- 独立文件比继续扩充 `ai.sh` 更容易维护，也更容易给 `deploy.sh` / 文档一个清晰职责边界。

## Trade-offs

- 同时支持 wrapper 与项目 settings 会增加一点实现量，但能覆盖“没项目随手开 Claude”和“项目里持久绑定 profile”两个真实场景。
- 只做 Bash/Zsh 版本会放弃 PowerShell 一致性，但实现更轻，桌面账号级切换可以复用 `ccswitch`。
- Bash/Zsh 版依赖 `jq` 更安全，仓库现有 shell helper 已有类似依赖和安装提示。
- 不写全局 `~/.claude/settings.json` 会让全局默认不随 profile 变化，但避免破坏仓库既有“全局 settings 是生成产物”的约定。
- 使用 JSON 处理工具能降低损坏 settings 的风险；若只依赖 shell 字符串拼接，短期快但后续维护成本高。

## Rollback

`claude-profile use` 写入前应保留临时文件写回策略。若更新失败，不覆盖原 `.claude/settings.local.json`。用户可手动删除项目 `.claude/settings.local.json` 中 profile 写入的 `env` 键恢复。
