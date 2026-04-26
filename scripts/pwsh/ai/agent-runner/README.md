# AI Agent Runner

`agent-runner` 是一个跨平台 PowerShell CLI，用来通过本机 coding agent 执行一次性 prompt。

安装 bin shim：

```powershell
pwsh -NoProfile -File ./Manage-BinScripts.ps1 -Action sync -Force
```

常用命令：

```powershell
./bin/Invoke-AiAgent.ps1 commit
./bin/Invoke-AiAgent.ps1 commit -ReasoningEffort high
./bin/Invoke-AiAgent.ps1 run "修复 failing tests，并执行 pnpm qa"
./bin/Invoke-AiAgent.ps1 run -PromptFile ./task.md -Agent claude
./bin/Invoke-AiAgent.ps1 run -Preset commit -Agent codex
```

## Prompt preset

内置 preset 位于 `prompts/*.md`，文件开头可以声明 frontmatter：

```markdown
---
agent: codex
reasoning_effort: medium
---

检查当前 Git 变更并提交 commit。
```

优先级从低到高：

1. 工具默认值
2. preset frontmatter
3. CLI 显式参数

## Agent 支持

- `codex`：支持 `model`、`reasoning_effort`、`json`、`work_dir`。
- `claude`：支持 `model`、`json`、`work_dir`，不映射 `reasoning_effort`。
- `opencode`：支持 `model`、`work_dir`，不映射 `reasoning_effort`。

`commit` preset 会让 agent 执行本地 `git commit`，不会执行 `git push`。

## 常见问题

- 未找到 CLI：先安装对应的 `codex`、`claude` 或 `opencode` 并完成登录。
- 没有 Git 变更：`commit` preset 应以非零退出码结束。
- 验证失败：修复验证命令报告的问题后重新运行。
- 需要透传 agent 私有参数：使用 `-ExtraArgs`。
