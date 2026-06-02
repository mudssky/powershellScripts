# Claude Code 多 key 切换工具

## Goal

在 Bash/Zsh 通用 shell 片段 `shell/shared.d/claude-profile.sh` 中提供 Claude Code profile 切换工具，让终端环境可以用一套轻量命令选择不同的 Anthropic API key、base URL、模型与 Claude Code 相关环境配置。PowerShell / 桌面账号级切换不纳入首版，桌面场景可继续使用 `ccswitch`。

用户价值：

- 不需要在不同项目之间手动复制 `ANTHROPIC_API_KEY`、`ANTHROPIC_BASE_URL` 和模型变量。
- 切换后可以通过 `claude-profile current` 明确看到当前项目使用的 profile。
- 没有项目目录时，也可以用 `claude-profile run glm` 这类命令直接启动 Claude Code。
- 在 Bash/Zsh 中使用一致的命令心智模型。
- 需要项目持久化时，仍可写入项目 `.claude/settings.local.json`，但桌面账号级切换交给 `ccswitch`。

## Confirmed Facts

- `shell/shared.d/ai.sh` 已存在，但它当前只承载通知/铃声类轻量 helper。
- 新的 Claude profile 命令更适合独立文件，而不是继续堆进 `ai.sh`。
- `shell/deploy.sh` 会把 `shell/shared.d/*.sh` symlink 到 `~/.bashrc.d/`，并让 Bash/Zsh rc loader 加载这些片段。
- 用户已将首版收敛为只做 shell 版本；PowerShell profile 与桌面账号级切换不纳入本任务。
- 仓库已有 Claude 配置分层：`ai/coding/claude/config/settings.json` 是可提交共享模板，`ai/coding/claude/config/settings.local.json` 是本机私有覆盖，`~/.claude/settings.json` 是生成产物。
- 仓库既有 Claude 文档明确要求不要直接手改 `~/.claude/settings.json` 作为长期入口。
- Context7 查询到的 Claude Code 文档确认：
  - `ANTHROPIC_API_KEY` 可作为环境变量使用，并会覆盖订阅登录。
  - `ANTHROPIC_BASE_URL` 是官方支持的网关 / proxy 入口。
  - Claude Code settings 的 `env` 可承载环境变量。
  - `--settings <file-or-json>` 是单次会话级覆盖，优先级高于 user/project/local，且可只覆盖指定键。
  - VS Code Claude 扩展会共享 Claude Code settings；项目级 settings 也是 Claude Code 支持的配置来源。
  - VS Code 侧还会读取 `~/.claude/settings.json`，并能通过 `CLAUDE_CONFIG_DIR` 迁移全局配置目录。
- 因此，单纯在当前 shell 里 `export` 变量只对当前终端进程树可靠，不是最兼容 VS Code 插件的方式。
- 将 profile 写入项目 `.claude/settings.local.json` 或项目 `.claude/settings.json` 的 `env`，更符合“每个项目选择 provider/profile”的目标；其中 `settings.local.json` 更适合 secrets 与本机差异。
- `claude-profile run` 更适合走会话级 `--settings` 覆盖或等价临时注入方式，把 profile 的 `env` 叠到当前启动参数里，同时保留 user/project/local 的其他配置。

## Requirements

- `shell/shared.d/claude-profile.sh` 承载 Bash/Zsh 版本的 profile 命令族，`shell/shared.d/ai.sh` 保持原有轻量 helper。
- 提供 `claude-profile use <profile>` 命令，从 `~/.claude/profiles/<profile>.json` 读取 profile。
- profile 文件采用 JSON，首版至少支持顶层 `env` 对象，用于写入 Claude Code 所需环境变量。
- `claude-profile use` 默认作用于当前工作目录所在项目，写入项目级 `.claude/settings.local.json`，避免把 secrets 写入可提交的 `.claude/settings.json`。
- `claude-profile use` 写入时必须创建 `.claude/` 目录，并保留已有 `.claude/settings.local.json` 中非 profile 管理字段。
- `claude-profile use` 写入时必须用 JSON 合并，而不是脆弱的字符串拼接。
- 提供 `claude-profile run <profile> [claude args...]`，使用指定 profile 的 env 直接启动 `claude`，不要求当前目录是项目，也不写项目 settings。
- `claude-profile run` 调用 `claude` 时应优先使用会话级 `--settings` 覆盖或等价临时注入方式，避免误伤用户已有 settings。
- 为常用 profile 提供一条命令启动的快捷入口，例如 `claude-profile run glm [claude args...]`。
- 提供 `claude-profile current` 命令，显示当前项目选择的 profile，以及生效的关键 env 键；输出不得泄露完整 API key。
- 提供 `claude-profile list` 或等价能力，列出 `~/.claude/profiles/*.json` 中可用 profile。
- 提供 `claude-profile add <profile>`，创建新的 profile 模板并立即打开编辑器。
- 提供清晰错误提示：profile 不存在、profile JSON 非法、缺少 `env`、当前目录不可写。
- 函数需要兼容 Bash/Zsh source，不依赖仅 Bash 可用的复杂语法，除非已有片段约定允许。
- 不把 profile JSON 或实际 key 写入仓库。

## Acceptance Criteria

- [ ] 在任意项目目录执行 `claude-profile use glm` 后，会生成或更新 `.claude/settings.local.json`，其中包含 profile 的 `env` 配置。
- [ ] 在任意非项目目录执行 `claude-profile run glm` 时，会使用 `glm` profile 的 env 启动 `claude`，且不会创建项目 `.claude/`。
- [ ] `claude-profile run` 在保留 user settings 的前提下，仍能让 profile 的 `env` 优先生效。
- [ ] `shell/shared.d/ai.sh` 仍只包含轻量 helper，不承载 profile 命令族。
- [ ] `shell/shared.d/claude-profile.sh` 可以被 `shell/deploy.sh` 正确加载到 Bash/Zsh。
- [ ] 已有 `.claude/settings.local.json` 的其他顶层配置不会被删除。
- [ ] `claude-profile current` 能显示当前 profile 名称和关键 provider/model 信息，并对 key 做脱敏。
- [ ] VS Code Claude 插件在项目中 Reload Window 后可通过 Claude Code settings 读取同一份项目配置。
- [ ] `claude-profile list` 能列出 `~/.claude/profiles/` 下的 profile。
- [ ] `claude-profile add glm` 会生成 profile 模板并打开编辑器，方便直接填写 `env`。
- [ ] 非法 profile 会失败且不破坏原有 `.claude/settings.local.json`。
- [ ] 根目录 `pnpm qa` 通过；如 QA 暴露与本改动相关问题，需要修复。

## Out of Scope

- 首版不开发交互式密钥录入或密钥加密存储。
- 首版不修改 `ai/coding/claude/Sync-ClaudeConfig.ps1` 的全局配置生成流程。
- 首版不把 Claude profile 命令继续塞进 `shell/shared.d/ai.sh`。
- 首版不直接写 `~/.claude/settings.json`。
- 首版不开发 PowerShell profile 版本。
- 首版不实现桌面账号级切换；该场景优先使用 `ccswitch`。
- 首版不自动启动、重载或控制 VS Code。

## Options Considered

- 当前 shell `export`：实现最简单，适合只在终端临时运行 `claude`；缺点是 VS Code 插件通常不是该 shell 的子进程，兼容性弱。
- 全局 `~/.claude/settings.json` 切换：CLI 与 VS Code 都容易读到；缺点是跨项目会互相覆盖，且仓库已有约定把它视为生成产物，不推荐手改。
- 项目 `.claude/settings.json`：项目内稳定可共享；缺点是容易把 secrets 提交，除非只放非敏感 provider 名称。
- 项目 `.claude/settings.local.json`：最适合 per-project + secrets + VS Code 兼容目标；缺点是需要确保 Claude Code / 插件加载 local settings，并且文件通常不提交，换机器需要重新设置。
- profile 目录 + symlink：很多现成工具会把不同配置拆成独立目录，再把 `~/.claude` 或 `~/.claude/settings.json` 指向当前 profile；优点是切换简单，缺点是更偏全局，不够项目化。
- 包装命令 `cc <profile>`：不会落盘 secrets，适合一次性终端运行；缺点是无法自然影响 VS Code 插件。

## Recommendation

首版采用 Bash/Zsh shell 双入口：

- `claude-profile run glm`：日常交互默认入口，一条命令临时带 profile env 启动 `claude`，没有项目也能使用。
- `claude-profile use glm`：需要让某个项目长期绑定 profile，尤其是希望 VS Code Claude 插件 Reload Window 后也读取同一 profile 时使用。

同一语义需要在 Bash/Zsh 中成立。这个组合比“先切换再手动启动 Claude”的两步流更贴近日常使用；也比只做 wrapper 更照顾项目持久化。
`run` 使用会话级覆盖或等价临时注入方式，让 profile env 优先生效，同时保留 user/project/local 的其他配置。

## Resolved Decisions

- 主入口采用 `claude-profile use/run/current/list` 这种子命令风格。
- `claude-profile add <profile>` 作为新 profile 的创建入口，生成模板后立即打开编辑器。
- Bash/Zsh 版的 profile 命令族从 `ai.sh` 拆到独立文件 `claude-profile.sh`。
- 首版只实现 Bash/Zsh 版本；PowerShell / 桌面账号级切换不做，桌面使用 `ccswitch`。

## Open Questions

- 是否额外保留短别名，例如 `cp use/run/current/list` 或 `cc-*`，作为主入口之外的快捷方式？

## Notes

- 用户示例中的 `glm` 与 `official` profile 是目标使用体验的核心参考。
