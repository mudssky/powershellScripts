# AI Agent Runner Presets Design

## Summary

本设计是 `AI Agent Runner` 的增量设计，目标是在已落地的 `Invoke-AiAgent.ps1` 基础上增强两个高频体验：

- 新增 `fix-tests` 内置 prompt preset 和快捷命令。
- 支持在 preset 或 prompt 文件的主 prompt 后追加结构化附加要求，例如 `commit -AppendPrompt "只提交暂存区"`。

范围刻意保持小：内置 preset 只保留 `commit` 与 `fix-tests` 两个高频场景，不引入 `review`、`refactor`、`qa` 等更多 preset，避免工具过早膨胀。

## Context

当前 `agent-runner` 已具备以下能力：

- `commit` 快捷命令会规约为 `run -Preset commit`。
- `run` 支持直接 prompt、`-PromptFile` 或 `-Preset` 三选一。
- prompt preset 使用 Markdown + frontmatter，`commit.md` 默认 `agent: codex` 和 `reasoning_effort: medium`。
- `-DryRun` 会隐藏 prompt 明文，只显示命令预览与 `PromptChars`。

现有缺口是：当用户选择 preset 或 prompt 文件时，无法临时补充一条局部约束。典型例子是 `commit` preset 默认会让 agent 检查 Git 变更并提交，但用户有时只想追加“只提交暂存区”。如果为每个细分场景都新增 preset，会导致 preset 数量快速膨胀；更适合的方式是保留少量稳定 preset，并允许 CLI 追加结构化要求。

## Goals

- 增加 `fix-tests` preset，用于定位并修复测试或 QA 失败。
- 增加 `fix-tests` 快捷命令，行为等价于 `run -Preset fix-tests`。
- 增加 `-AppendPrompt <string[]>`，允许对直接 prompt、prompt 文件或 preset 追加附加要求。
- 附加要求使用稳定 Markdown 结构追加到最终 prompt 尾部，降低 agent 误解概率。
- 保持 prompt 来源三选一规则不变：直接 prompt、`-PromptFile`、`-Preset` 仍然必须且只能提供一种。
- 保持 `-DryRun` 安全行为：不打印 prompt 明文，`PromptChars` 基于合成后的最终 prompt。

## Non-Goals

- 不新增 `review`、`refactor`、`qa`、`explain` 等更多 preset。
- 不实现 preset include、preset 组合或模板语言。
- 不改变 `psutils/src/config` 的配置解析能力。
- 不改变 `Manage-BinScripts.ps1` 的目录型工具安装规则。
- 不让 `fix-tests` 自动提交 commit 或 push。

## CLI Design

保留现有命令：

```powershell
./bin/Invoke-AiAgent.ps1 commit
./bin/Invoke-AiAgent.ps1 run -Preset commit
./bin/Invoke-AiAgent.ps1 run -PromptFile ./task.md
```

新增快捷命令：

```powershell
./bin/Invoke-AiAgent.ps1 fix-tests
./bin/Invoke-AiAgent.ps1 run -Preset fix-tests
```

新增追加参数：

```powershell
./bin/Invoke-AiAgent.ps1 commit -AppendPrompt "只提交暂存区"
./bin/Invoke-AiAgent.ps1 fix-tests -AppendPrompt "只修复 Pester 失败"
./bin/Invoke-AiAgent.ps1 run -PromptFile ./task.md -AppendPrompt "不要修改文档"
./bin/Invoke-AiAgent.ps1 commit -AppendPrompt "只提交暂存区","不要修改未暂存文件"
```

`-AppendPrompt` 不是新的 prompt 来源，而是最终 prompt 的附加约束。因此它可以与直接 prompt、`-PromptFile` 或 `-Preset` 共存，不参与三选一计数。

## Prompt Composition

最终 prompt 由两部分组成：

1. 主 prompt：来自直接 prompt、prompt 文件或 preset。
2. 可选附加要求：来自 `-AppendPrompt`。

当存在附加要求时，runner 在主 prompt 后追加固定 Markdown 结构：

```markdown
## 附加要求

- 只提交暂存区
- 不要修改未暂存文件
```

组合规则：

- 忽略空字符串或纯空白的追加项。
- 单条追加项也使用列表格式，保持结构一致。
- 多条追加项按 CLI 传入顺序输出。
- 主 prompt 与附加要求之间保留空行。
- `PromptChars` 统计合成后的最终 prompt 长度。
- `Format-AiAgentCommandPreview` 继续用 `<PROMPT>` 替代 prompt 明文。

## Preset Design

`commit` preset 保持现有核心行为，并允许通过 `-AppendPrompt` 增加局部约束：

- 默认 `agent: codex`。
- 默认 `reasoning_effort: medium`。
- 检查当前 Git 变更。
- 遵循 Conventional Commits 规范生成中文 commit message。
- 必要时执行仓库要求的验证命令。
- 验证通过后执行 `git commit`。
- 不执行 `git push`。

`fix-tests` preset 新增为 `scripts/pwsh/ai/agent-runner/prompts/fix-tests.md`：

- 默认 `agent: codex`。
- 默认 `reasoning_effort: medium`。
- 优先根据用户提供的失败输出或上下文定位失败原因。
- 如果缺少失败输出，先运行与当前仓库最相关的最小验证命令获取证据。
- 做最小必要修改，避免无关重构。
- 修复后重新运行同一个失败命令确认。
- 涉及 PowerShell 相关改动时遵守仓库测试规则。
- 不主动执行 `git commit`，不执行 `git push`。
- 如果测试仍失败，以非零退出码结束并说明原因。

## Implementation Boundaries

实现只触碰 `agent-runner` 及其测试文档：

- `scripts/pwsh/ai/agent-runner/main.ps1`：新增 `-AppendPrompt <string[]>` 参数，并传入执行路径。
- `scripts/pwsh/ai/agent-runner/core/arguments.ps1`：新增 `fix-tests` 快捷命令映射。
- `scripts/pwsh/ai/agent-runner/core/prompt.ps1`：新增 prompt 组合逻辑。
- `scripts/pwsh/ai/agent-runner/prompts/fix-tests.md`：新增 preset。
- `scripts/pwsh/ai/agent-runner/README.md`：补充 `fix-tests` 与 `-AppendPrompt` 示例。
- `tests/AiAgentRunner.Tests.ps1`：补充参数、组合和 dry-run 相关测试。

不需要修改：

- `psutils/src/config/**`
- `Manage-BinScripts.ps1`
- `tool.psd1`
- `bin/Invoke-AiAgent.ps1` 的安装规则

## Testing

需要覆盖以下行为：

- `fix-tests` 快捷命令规约为 `run -Preset fix-tests`。
- `Read-AiAgentPromptPreset` 能读取 `fix-tests` metadata，且默认推理强度为 `medium`。
- `Resolve-AiAgentPromptText` 或新的组合函数能把主 prompt 与 `-AppendPrompt` 合成为结构化 Markdown。
- `-AppendPrompt` 可以与 preset 共存。
- `-AppendPrompt` 可以与 prompt 文件共存。
- 多条 `-AppendPrompt` 按顺序追加为列表。
- 空白追加项不会进入最终 prompt。
- prompt 来源三选一规则保持不变。
- public dry-run 不泄漏 prompt 明文，且 `PromptChars` 基于合成后的 prompt。

验证命令沿用仓库规则：

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/AiAgentRunner.Tests.ps1 -Output Detailed"
pnpm qa
pnpm test:pwsh:all
```

## Risks

- 如果 `-AppendPrompt` 命名过宽，后续可能被误用为完整 prompt 来源。文档中需要明确它是“附加要求”，不是替代 `Prompt`。
- 附加要求拼接为 Markdown 列表时，用户传入多行文本可能形成复杂列表项。首版不做模板解析，仅原样作为列表项内容输出。
- `fix-tests` preset 可能和仓库级 QA 规则重叠。preset 应描述“根据上下文选择最小验证命令”，不强制每次都跑完整测试套件。

