# 迁移 powershellscripts-ops 到 dev skill 设计

## Scope

本任务只迁移并安装 `powershellscripts-ops`：

- 来源从 `.agents/skills/repo-ops/` 迁移到 `ai/skills/dev/powershellscripts-ops/`。
- `name` 从过泛的 `repo-ops` 改为 `powershellscripts-ops`。
- `ai/skills/skills.config.json` 新增 `powershellscripts-ops` 本地 skill 配置，使用现有 `Install-Skills.ps1` 安装到 global。
- 不纳入 `.agents/skills/trellis-*`，不新增单独安装辅助 skill。
- 不推荐 project scope 安装，避免 global 与 project 中出现重复入口。

## Architecture

迁移后的目录结构：

```text
ai/skills/dev/powershellscripts-ops/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── references/
    ├── forgejo.md
    ├── litellm.md
    ├── lobehub.md
    ├── n8n.md
    ├── project-install.md
    └── skill-maintenance.md
```

`powershellscripts-ops` 仍是纯文档型 skill，不新增脚本入口。仓库操作继续由 Agent 根据 reference 调用现有项目脚本和命令。

## Repository Location Contract

全局安装时，`powershellscripts-ops` 可能被复制到 `~/.codex/skills/powershellscripts-ops` 或 `~/.claude/skills/powershellscripts-ops`，不能依赖安装目录就是仓库目录。

`SKILL.md` 增加仓库定位规则：

1. 优先读取环境变量 `POWERSHELLSCRIPTS_REPO`。
2. 未设置时使用兜底路径 `/Users/mudssky/projects/env/powershellScripts`。
3. 执行仓库命令前，先确认该目录存在且包含预期文件，例如 `ai/skills/Install-Skills.ps1` 或 `.git`。
4. 如果路径不存在，要求用户提供当前仓库路径，不猜测或在其他目录执行破坏性操作。

这样当前机器开箱即用，同时保留未来迁移路径的可配置性。

## Installation Contract

`ai/skills/skills.config.json` 新增：

```json
"powershellscripts-ops": {
  "description": "管理 powershellScripts 仓库运维任务与项目依赖安装。",
  "source": "./dev/powershellscripts-ops",
  "sourceType": "local"
}
```

安装继续使用现有命令：

```powershell
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name powershellscripts-ops -DryRun
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name powershellscripts-ops -Yes
```

project scope 不是本任务推荐安装方式；该 skill 绑定固定仓库，重复安装到项目和全局会制造同功能入口。

## Compatibility

- 已安装的旧 `.agents/skills/repo-ops` 路径不再作为维护来源。
- `.agents/skills/` 仍保留 Trellis skill 与其它项目级 skill，不整体迁移。
- 文档中涉及 `repo-ops` 维护路径的引用要更新为 `ai/skills/dev/powershellscripts-ops`。
- `agents/openai.yaml` 随目录迁移保留；如内容仍匹配无需重生成。

## Rollback

如果迁移后安装或校验失败：

- 将 `ai/skills/dev/powershellscripts-ops/` 移回 `.agents/skills/repo-ops/`，并恢复 `name: repo-ops`。
- 移除 `ai/skills/skills.config.json` 中的 `powershellscripts-ops` 项。
- 回退文档中路径引用。

不需要修改用户全局 skill 目录作为回滚前提；真实安装动作在 dry-run 后再执行。
