# 通用 Skill 开发规范

本目录用于维护可跨多个 agent 复用的个人 skill。稳定后可以通过 `Install-Skills.ps1`
安装到 Claude、Codex 等 agent；仍在实验中的内容先放在 `dev/` 下。

## 目录结构

推荐每个 skill 使用独立目录：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  references/
  examples/
  scripts/
```

`SKILL.md` 是唯一必需文件。`references/` 放长文档或外部资料摘要，`examples/`
放可复制的使用示例，`scripts/` 放该 skill 专属辅助脚本。

## SKILL.md Frontmatter

每个 `SKILL.md` 必须包含 frontmatter：

```markdown
---
name: my-skill
description: 一句话说明触发场景和能力边界。
---
```

要求：

- `name` 使用小写短横线命名，并与目录名保持一致。
- `description` 用中文描述“什么时候使用”，避免只写功能名。
- 不写入单一 agent 私有字段；需要 agent 差异时放在正文的兼容性说明中。

## 内容组织

正文建议按这个顺序：

1. 使用时机：明确哪些请求会触发该 skill。
2. 工作流程：列出 agent 执行任务时应遵循的步骤。
3. 约束边界：说明不要做什么、何时应改用其他工具。
4. 资源引用：只链接必要的 `references/`、`examples/` 或 `scripts/` 文件。

## 脚本与依赖

如果 skill 依赖额外 CLI 或运行环境，不要把安装副作用写进 `SKILL.md`。
应在 `skills.config.json` 中为该 skill 配置 `commands`，例如：

```json
{
  "my-playwright-skill": {
    "description": "使用 Playwright 做浏览器自动化。",
    "source": "./dev/my-playwright-skill",
    "sourceType": "local",
    "commands": [
      {
        "name": "install-playwright-browsers",
        "phase": "postInstall",
        "command": "npx",
        "args": ["playwright", "install", "--with-deps"]
      }
    ]
  }
}
```

安装脚本会把这些命令纳入 dry-run、确认、日志和 `ShouldProcess` 链路。

## 本地开发到安装

默认只安装 `skills.config.json` 显式列出的本地 skill。需要临时同步全部本地开发
skill 时，可执行：

```powershell
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -IncludeDevAll -DryRun
```

确认计划正确后移除 `-DryRun`。远程和本地 skill 都通过 `npx skills add` 安装，
安装状态与 lock 文件由 `skills` CLI 维护。
