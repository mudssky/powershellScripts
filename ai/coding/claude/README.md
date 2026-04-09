# Claude 配置与工具说明

这个目录承载本仓库里与 Claude Code 相关的配置、同步脚本、文档和本地 Skill 开发入口。

如果你只想知道怎么开始，用最短路径：

1. 在 `ai/coding/claude/config/settings.local.json` 写入本机 secrets 或 provider 覆盖。
2. 运行 `pwsh -NoProfile -File ./ai/coding/claude/Sync-ClaudeConfig.ps1`。
3. 让脚本生成并更新 `~/.claude/settings.json`，以及同步受管共享资产。

## 目录说明

```text
ai/coding/claude/
├── .claude/                    # 受管共享资产源，不是最终运行目录
├── config/
│   ├── settings.json           # 可提交的共享模板
│   └── settings.local.json     # 本机私有覆盖（可选，不提交 Git）
├── docs/                       # Claude 相关说明与备忘
├── skills-dev/                 # 本地开发中的 Skill 源目录
├── Sync-ClaudeConfig.ps1       # 配置生成与共享资产同步入口
├── Manage-ClaudeSkills.ps1     # Skill 安装 / 卸载 / 导出 / watch 工具
└── install.ps1                 # 当前保留的快捷安装入口
```

## 当前配置模型

本仓库采用的是“两层源 + 一层生成产物”的模型：

### 1. 共享模板

文件：`ai/coding/claude/config/settings.json`

这里放：

- 团队共享的默认权限
- 非敏感 `env` 默认值
- 默认模型、状态栏、插件开关
- 适合提交审阅的长期配置

这里不应放：

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_BASE_URL`
- 任何 token / secret / password

### 2. 本机覆盖

文件：`ai/coding/claude/config/settings.local.json`

这是可选文件，不提交 Git。这里适合放：

- API key
- 本机代理 / router 地址
- 临时模型切换
- 个人偏好覆盖

示例：

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "sk-ant-...",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456"
  },
  "model": "opus[1m]"
}
```

### 3. 生成产物

文件：`~/.claude/settings.json`

这是最终生效配置，由 `Sync-ClaudeConfig.ps1` 生成。不要把它当成长期手改入口。

如果要改行为，优先改：

- 共享默认值：`config/settings.json`
- 本机差异：`config/settings.local.json`

而不是直接改 `~/.claude/settings.json`。

## 合并规则

`Sync-ClaudeConfig.ps1` 会按下面的规则合并 shared template 与 local override：

- 标量：local 覆盖 shared
- 对象：深度合并
- 数组：拼接后按内容去重

这意味着你只需要在 `settings.local.json` 里声明差异项，不需要复制整个对象。

例如：

- 只想补一个 `env.ANTHROPIC_API_KEY`
- 只想把某个 `enabledPlugins.xxx` 改成 `true`
- 只想覆盖 `model`

都只写这些字段即可。

## `Sync-ClaudeConfig.ps1` 做了什么

运行命令：

```powershell
pwsh -NoProfile -File ./ai/coding/claude/Sync-ClaudeConfig.ps1
```

脚本会做这些事：

1. 读取 `config/settings.json`
2. 读取可选的 `config/settings.local.json`
3. 检查共享模板里是否误放了明显的 secrets
4. 生成最终的 `~/.claude/settings.json`
5. 同步 `.claude/` 下的受管共享资产到真实的 `~/.claude`

### 在新机器上执行

如果机器上还没有 `~/.claude`：

- 不会创建软连接
- 会直接创建真实目录 `~/.claude`
- 会生成 `~/.claude/settings.json`
- 会把受管共享资产复制进去

### 在已有 `~/.claude` 的机器上执行

如果 `~/.claude` 已经存在：

- `~/.claude/settings.json` 会被重新生成并覆盖
- 受管共享资产会按白名单覆盖更新
- 非受管运行态文件会尽量保留

### 在旧软连接机器上执行

如果之前是旧模式：

```text
~/.claude -> repo/.claude
```

脚本会：

1. 先做备份
2. 删除旧软连接
3. 创建真实的 `~/.claude` 目录
4. 恢复备份内容
5. 再写入生成的 settings 和受管资产

也就是说，当前脚本的目标是**结束整目录软连接模式**，回到真实的用户配置目录。

## 会同步哪些文件

当前受管白名单包括：

- `CLAUDE.md`
- `config.json`
- `commands/*.md`
- `output-styles/*.md`
- `ccline/config.toml`
- `ccline/models.toml`
- `ccline/themes/*.toml`
- `skills/**/*.md`

同步后目标目录里还会写一个内部清单：

- `.sync-manifest.json`

这个文件用于记录“哪些文件是脚本管理的”，方便后续清理仓库里已经删除的旧受管文件。

## 不会主动管理哪些内容

这些通常属于 Claude 运行时生成内容，不作为仓库共享配置管理：

- `history.jsonl`
- `debug/`
- `sessions/`
- `transcripts/`
- `projects/`
- 其他缓存、锁文件、统计文件

因此：

- 仓库负责“共享配置和共享资产”
- `~/.claude` 负责“真实运行时状态”

## 推荐使用流程

### 场景 1：首次配置

1. 准备 `config/settings.local.json`
2. 运行 `Sync-ClaudeConfig.ps1`
3. 启动 Claude
4. 让 Claude 自己生成运行态目录和历史文件

### 场景 2：更新共享默认配置

1. 修改 `config/settings.json`
2. 提交到仓库
3. 在目标机器运行 `Sync-ClaudeConfig.ps1`

### 场景 3：只改本机 secrets 或 router

1. 修改 `config/settings.local.json`
2. 重新运行 `Sync-ClaudeConfig.ps1`

### 场景 4：切换到新机器

1. 拉取仓库
2. 新建本机 `config/settings.local.json`
3. 运行 `Sync-ClaudeConfig.ps1`

## `Manage-ClaudeSkills.ps1` 用来做什么

这个脚本主要服务于 `skills-dev/` 目录中的本地 Skill 开发。

它支持：

- 查看 Skill 列表
- 安装 / 更新 Skill 到 `.claude/skills`
- 卸载 Skill
- watch 模式同步
- 导出 Skill 压缩包

交互式运行：

```powershell
pwsh -NoProfile -File ./ai/coding/claude/Manage-ClaudeSkills.ps1
```

也可以传动作参数，例如：

```powershell
pwsh -NoProfile -File ./ai/coding/claude/Manage-ClaudeSkills.ps1 -Action List
pwsh -NoProfile -File ./ai/coding/claude/Manage-ClaudeSkills.ps1 -Action Install -SkillName my-skill
```

注意：这个脚本当前把 `ai/coding/claude/.claude/skills` 当作 Skill 的目标目录，也就是“仓库里的受管共享资产源”，而不是直接写入用户真实的 `~/.claude/skills`。要让这些 Skill 最终进入用户目录，仍然要再跑一次 `Sync-ClaudeConfig.ps1`。

## 常见问题

### 1. 为什么 `settings.local.json` 没提交？

因为这是本机私有覆盖层，通常会包含 secrets 或个人差异配置，不应该进 Git。

### 2. 为什么不能直接改 `~/.claude/settings.json`？

因为它是生成产物。你下次跑 sync 时，这个文件会被重新写出。

### 3. 我只想走 router，不想在模板里放 `ANTHROPIC_BASE_URL`

把它放到 `config/settings.local.json` 即可。共享模板应该只保留安全的默认值。

### 4. 如果共享模板里不小心放了 key 会怎样？

`Sync-ClaudeConfig.ps1` 会在写入前直接报错并阻止生成，提醒你把敏感内容移到 `config/settings.local.json`。

### 5. 我的 `~/.claude/skills` 里有自己手加的内容，会被删吗？

脚本只管理白名单和它自己记录过的受管文件。额外的非受管内容通常会保留。

## 相关文档

- `ai/coding/claude/docs/config.md`
- `ai/coding/claude/docs/CLAUDE_CODE_CHEATSHEET.md`
- `ai/coding/claude/docs/CLAUDE_CODE_ADVANCED_FEATURES.md`
- `ai/coding/claude/docs/CLAUDE_CODE_AGENT_SKILL_CHEATSHEET.md`
- `ai/coding/claude/docs/CLAUDE_CODE_SUB_AGENT_CHEATSHEET.md`
- `ai/coding/claude/docs/CLAUDE_CODE_WORKFLOW_CHEATSHEET.md`
