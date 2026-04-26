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
./bin/Invoke-AiAgent.ps1 commit -AppendPrompt "只提交暂存区"
./bin/Invoke-AiAgent.ps1 fix-tests
./bin/Invoke-AiAgent.ps1 fix-tests -AppendPrompt "只修复 Pester 失败"
./bin/Invoke-AiAgent.ps1 run "修复 failing tests，并执行 pnpm qa"
./bin/Invoke-AiAgent.ps1 run -PromptFile ./task.md -Agent claude -AppendPrompt "不要修改文档"
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

`commit` preset 会让 agent 执行本地 `git commit`，不会执行 `git push`。

`fix-tests` preset 会让 agent 定位并修复测试或 QA 失败，修复后重新运行失败命令确认；它不会主动执行 `git commit` 或 `git push`。

## 附加要求

`-AppendPrompt` 可以在主 prompt 后追加临时约束，适用于 preset、prompt 文件和直接 prompt。runner 会把内容整理为 Markdown 列表：

```powershell
./bin/Invoke-AiAgent.ps1 commit -AppendPrompt "只提交暂存区","不要修改未暂存文件"
```

该参数不算新的 prompt 来源，因此不会破坏 `Prompt`、`PromptFile`、`Preset` 三选一规则。

## Agent 支持

- `codex`：支持 `model`、`reasoning_effort`、`json`、`work_dir`。
- `claude`：支持 `model`、`json`、`work_dir`，不映射 `reasoning_effort`。
- `opencode`：支持 `model`、`work_dir`，不映射 `reasoning_effort`。

## 常见问题

- 未找到 CLI：先安装对应的 `codex`、`claude` 或 `opencode` 并完成登录。
- 没有 Git 变更：`commit` preset 应以非零退出码结束。
- 验证失败：修复验证命令报告的问题后重新运行。
- 需要透传 agent 私有参数：使用 `-ExtraArgs`。
