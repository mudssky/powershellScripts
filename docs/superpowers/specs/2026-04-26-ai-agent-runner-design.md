# AI Agent Runner Design

## Summary

本设计定义一个跨平台 PowerShell CLI，用来通过本机 coding agent 执行一次性任务 prompt，并内置常用 prompt preset。第一版放在 `scripts/pwsh/ai/agent-runner/`，通过目录型工具 manifest 安装为 `bin/Invoke-AiAgent.ps1`。

工具首批支持 `codex`、`claude`、`opencode` 三个 agent。核心体验是：

- 直接运行预置任务，例如 `Invoke-AiAgent.ps1 commit`。
- 运行自定义 prompt，例如 `Invoke-AiAgent.ps1 run "修复 failing tests，并执行 pnpm qa"`。
- prompt preset 使用 Markdown 文件维护，frontmatter 声明默认 agent、模型、推理强度等元数据。
- CLI 显式参数参与统一配置优先级，覆盖 prompt frontmatter 与工具默认值。
- `commit` 预置直接让 agent 完成 `git commit` 后退出，不执行 `git push`。

同时，本设计会补齐两个通用基础能力：

- `Manage-BinScripts.ps1` 支持目录型 PowerShell 工具 manifest，只安装公开入口，不暴露内部脚本。
- `psutils/src/config` 扩展配置来源解析能力，并新增 `README.md` 说明如何复用与扩展。

## Context

当前仓库已经有几类相关基础：

- `scripts/pwsh` 下已有多个跨平台 PowerShell 工具，常见结构是严格模式、注释帮助、Pester 测试和 `bin` shim。
- `scripts/pwsh/devops/postgresql` 已经采用“入口脚本 + core/commands/platforms”的目录化源码结构。
- `Manage-BinScripts.ps1` 当前会扫描 `.ps1` / `.py` 文件生成 `bin` shim，但会把目录型工具的内部 `.ps1` 也暴露出去。
- `psutils/src/config` 已经提供配置来源解析、优先级合并、dotenv / JSON 读取和临时环境变量注入。
- `ai/coding/claude/skills-dev/coding-agent-runner/scripts/invoke_coding_agent.py` 已有一个 Python 原型，封装了 `codex`、`claude`、`opencode` 的基础调用方式。

用户需求收敛为：

- 在 `scripts/pwsh/ai/` 下新增一个独立工具目录。
- 工具目录名为 `agent-runner`。
- 安装后的公开命令名为 `Invoke-AiAgent.ps1`。
- 首版支持 `codex`、`claude`、`opencode`，默认 agent 为 `codex`。
- 内置 prompt preset 放在 Markdown 文件中。
- `commit` preset 默认使用 `medium` 推理强度，直接提交 commit，不 push。
- 配置解析应复用并扩展 `psutils/modules` / `psutils/src/config`，并支持 CLI 参数加入优先级。
- `agent-runner` 目录本身需要 `README.md`。
- `psutils/src/config` 需要新增 `README.md`。

## Goals

- 提供一个跨平台的 AI agent 执行入口，适配 `codex`、`claude`、`opencode`。
- 支持预置 prompt 与自定义 prompt 两种工作流。
- 让 prompt preset 能通过 Markdown frontmatter 声明默认配置。
- 让 CLI 显式参数作为最高优先级配置来源参与合并。
- 建立目录型 PowerShell 工具的安装规范，避免内部脚本被安装到 `bin`。
- 扩展 `psutils` 配置解析器，使 `.psd1`、Markdown frontmatter、CLI 参数都成为可复用的配置来源。
- 为 `agent-runner` 和 `psutils/src/config` 提供中文 README。
- 用 Pester 覆盖核心解析、命令构造和安装规则，不依赖真实 agent 网络调用。

## Non-Goals

- 不实现 agent 交互式会话管理、resume、session browser 或 TUI。
- 不在第一版实现多 agent 并行调度。
- 不替用户自动 push、创建 PR 或操作远端仓库。
- 不把 agent 输出解析成统一事件流；第一版透传外部 CLI 输出和退出码。
- 不在第一版为 `claude` / `opencode` 强行模拟 `reasoning_effort`。
- 不把 prompt preset 做成复杂模板语言；第一版只拼接静态 Markdown 正文。

## Chosen Approach

采用“目录型 PowerShell CLI + 通用配置解析扩展”的方案。

`agent-runner` 自身保持小而清晰的目录结构：入口脚本只负责加载模块与分发，`core/` 负责通用逻辑，`agents/` 负责外部 CLI 参数映射，`prompts/` 负责内置 preset。公开安装入口由 `tool.psd1` 声明，再由 `Manage-BinScripts.ps1` 生成 `bin/Invoke-AiAgent.ps1` shim。

`psutils/src/config` 只新增通用配置来源解析，不引入 AI 业务概念。`agent-runner` 通过这些解析能力组合工具默认值、prompt frontmatter 和 CLI 参数，形成最终执行配置。

这个方案比把所有逻辑放进一个大脚本更适合长期维护，也比只做局部解析器更利于后续复用。

## Source Layout

新增工具目录：

```text
scripts/pwsh/ai/agent-runner/
├── README.md
├── tool.psd1
├── main.ps1
├── core/
│   ├── arguments.ps1
│   ├── config.ps1
│   ├── prompt.ps1
│   └── process.ps1
├── agents/
│   ├── codex.ps1
│   ├── claude.ps1
│   └── opencode.ps1
└── prompts/
    └── commit.md
```

模块边界：

- `main.ps1`：公开入口，负责参数声明、加载依赖、顶层分发与退出码处理。
- `core/arguments.ps1`：解析子命令和剩余参数，生成结构化执行请求。
- `core/config.ps1`：组合默认值、preset metadata、CLI 参数，生成最终配置。
- `core/prompt.ps1`：解析 preset、读取 prompt 文件、合成最终 prompt 文本。
- `core/process.ps1`：检查外部命令、执行进程、透传退出码。
- `agents/*.ps1`：只负责把统一配置转换为具体 agent CLI 参数。
- `prompts/*.md`：保存内置 prompt preset。
- `README.md`：说明安装、命令示例、preset 维护方式、支持的 agent 与限制。

`tool.psd1` 示例：

```powershell
@{
    BinName = 'Invoke-AiAgent.ps1'
    Entry   = 'main.ps1'
}
```

## Directory Tool Install Spec

`Manage-BinScripts.ps1` 新增目录型工具 manifest 规则：

- 默认扫描 `scripts/pwsh/**/tool.psd1`。
- 使用 `Import-PowerShellDataFile` 读取 manifest。
- `BinName` 必填，必须是 `.ps1` 文件名。
- `Entry` 必填，必须指向 manifest 同目录下存在的 `.ps1` 文件。
- 只为 `Entry` 生成 `BinName` shim。
- manifest 所在目录下的其他 `.ps1` 默认视为内部实现，不生成公开 shim。
- 现有单文件 `.ps1` / `.py` shim 行为保持兼容。

这样 `scripts/pwsh/ai/agent-runner/core/*.ps1`、`agents/*.ps1` 不会出现在 `bin` 中，只会生成：

```text
bin/Invoke-AiAgent.ps1
```

后续其他目录型 PowerShell 工具也可以复用同一规范。

## CLI Design

公开命令支持预置和自定义 prompt：

```powershell
Invoke-AiAgent.ps1 commit
Invoke-AiAgent.ps1 commit -Agent codex
Invoke-AiAgent.ps1 run "修复 failing tests，并执行 pnpm qa"
Invoke-AiAgent.ps1 run -PromptFile ./task.md -Agent claude
Invoke-AiAgent.ps1 run -Preset commit -ReasoningEffort high
```

顶层命令：

- `commit`：快捷命令，等价于运行 `commit` preset。
- `run`：通用执行命令，支持 prompt 字符串、prompt 文件或 preset。
- `help`：输出工具帮助。

通用参数：

- `-Agent codex|claude|opencode`
- `-Model <string>`
- `-ReasoningEffort minimal|low|medium|high|xhigh`
- `-WorkDir <path>`
- `-Prompt <string>`
- `-PromptFile <path>`
- `-Preset <name>`
- `-Json`
- `-DryRun`
- `-Verbose`
- `-ExtraArgs <string[]>`

参数优先级从低到高：

1. 工具默认值。
2. prompt preset frontmatter。
3. CLI 显式参数。

CLI 参数必须作为 `psutils` 配置来源参与合并，而不是在业务代码里用零散 if/else 覆盖。

## Prompt Presets

内置 preset 使用 Markdown 文件：

```text
scripts/pwsh/ai/agent-runner/prompts/commit.md
```

`commit.md` 示例：

```markdown
---
agent: codex
reasoning_effort: medium
---

检查当前 Git 变更，遵循 Conventional Commits 规范生成中文 commit message。
必要时执行仓库要求的验证命令。
验证通过后执行 git commit。
不要执行 git push。
```

`commit` 行为：

- 直接让 agent 完成 commit 后退出。
- 只提交本地 commit，不 push。
- 遵循仓库要求的 Conventional Commits 格式，subject 使用中文。
- 如果没有可提交变更、验证失败或提交失败，应让 agent 以非零退出码结束；runner 透传退出码。

`run` 支持三种 prompt 来源：

- 直接字符串：`Invoke-AiAgent.ps1 run "..."`。
- 文件：`Invoke-AiAgent.ps1 run -PromptFile ./task.md`。
- preset：`Invoke-AiAgent.ps1 run -Preset commit`。

## psutils Config Extensions

`psutils/src/config` 新增配置来源类型：

- `PowerShellDataFile`：读取 `.psd1`，用于目录工具 manifest。
- `MarkdownFrontMatter`：读取 Markdown frontmatter，返回 metadata，并保留正文。
- `CliParameters`：把 `$PSBoundParameters` 或过滤后的 CLI 参数转换为配置来源。

`Resolve-ConfigSources` 保持“后出现覆盖先出现”的合并规则。`agent-runner` 使用示例：

```powershell
Resolve-ConfigSources -Sources @(
    @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ agent = 'codex' } }
    @{ Type = 'MarkdownFrontMatter'; Name = 'PromptPreset'; Path = './prompts/commit.md' }
    @{ Type = 'CliParameters'; Name = 'Cli'; Data = $PSBoundParameters }
)
```

`MarkdownFrontMatter` 第一版支持简单 YAML 子集：

- `key: value`
- 字符串
- 布尔值
- 数字

第一版不支持嵌套对象、数组、多行 YAML 值。遇到非法 frontmatter 时应返回包含文件路径和行号的中文错误。

`CliParameters` 规则：

- 只纳入调用方显式传入的参数。
- 过滤掉仅用于控制流程、不属于配置的键，例如内部 `RawArguments`。
- 参数名转换为下划线风格，例如 `ReasoningEffort` -> `reasoning_effort`。
- `$null` 与空字符串默认不覆盖已有值。

`psutils/modules/config.psm1` 和 `psutils/psutils.psd1` 需要导出新增公共函数。`psutils/src/config/README.md` 用中文说明：

- 已支持的 source 类型。
- source 优先级规则。
- CLI 参数如何作为 source 参与合并。
- `.psd1` 与 Markdown frontmatter 示例。
- 如何新增 source 类型。

## Agent Mapping

统一配置字段：

- `agent`
- `model`
- `reasoning_effort`
- `work_dir`
- `json`
- `dry_run`
- `extra_args`
- `prompt`

`codex` 映射：

- `model` -> `--model`
- `reasoning_effort` -> `-c model_reasoning_effort="<value>"`
- `work_dir` -> `-C`
- `json` -> `--json`
- `prompt` -> `codex exec [options] <prompt>`

`claude` 映射：

- `model` -> `--model`
- `json` -> `--output-format json`
- `work_dir` -> 进程工作目录
- `prompt` -> `claude -p <prompt> --setting-sources user,project,local`
- `reasoning_effort` 第一版不映射；verbose 模式可提示该 agent 不支持此统一字段。

`opencode` 映射：

- `model` -> `--model`
- `work_dir` -> 进程工作目录
- `prompt` -> `opencode run <prompt>`
- `json` 第一版不做统一映射，必要时通过 `-ExtraArgs` 透传。
- `reasoning_effort` 第一版不映射；verbose 模式可提示该 agent 不支持此统一字段。

外部命令不存在时，返回明确中文错误，例如：

```text
未找到 codex，请先安装并完成登录。
```

## Error Handling

内部执行结果使用统一结构：

```powershell
[pscustomobject]@{
    ExitCode = 0
    Output   = '...'
}
```

错误处理原则：

- 外部 agent 退出码原样透传。
- runner 自身配置错误返回非零退出码。
- 错误信息使用中文，包含足够定位信息。
- `DryRun` 只输出将执行的命令预览，不调用真实 agent。
- 命令预览不打印完整 prompt 内容，只显示 prompt 字符数或安全摘要，避免日志过长。
- 不打印 API key、token、password 等敏感环境变量。

典型错误：

- 未找到 agent CLI。
- prompt preset 不存在。
- prompt 文件不存在。
- frontmatter 格式非法。
- `tool.psd1` 缺少 `BinName` 或 `Entry`。
- manifest 指向的入口不存在。

## README Requirements

`scripts/pwsh/ai/agent-runner/README.md` 需要包含：

- 工具用途。
- 安装方式：运行 `Manage-BinScripts.ps1 -Action sync -Force` 后使用 `bin/Invoke-AiAgent.ps1`。
- `commit`、`run`、`PromptFile`、`Preset` 示例。
- prompt preset 文件结构与 frontmatter 字段说明。
- 三个 agent 的支持状态和参数映射差异。
- `reasoning_effort` 目前只有 `codex` 会映射的说明。
- `commit` 只 commit 不 push 的说明。
- 常见问题：未安装 CLI、未登录、没有 Git 变更、验证失败。

`psutils/src/config/README.md` 需要面向通用配置解析器，不出现 AI runner 业务细节，只用它作为一个调用示例即可。

## Testing Plan

新增或更新 Pester 测试：

- `psutils` 配置测试：
  - 读取 `.psd1`。
  - 解析 Markdown frontmatter。
  - frontmatter 非法行报错含路径与行号。
  - CLI 参数 source 转换为下划线键。
  - CLI source 覆盖 frontmatter，frontmatter 覆盖默认值。
- `Manage-BinScripts.ps1` 测试：
  - 目录工具 manifest 生成指定 `BinName`。
  - 内部 `core/*.ps1` 不生成 shim。
  - manifest 缺少入口时失败。
  - 现有单文件脚本同步行为保持兼容。
- `agent-runner` 测试：
  - `commit` 加载 `prompts/commit.md`，默认 `reasoning_effort` 为 `medium`。
  - CLI `-ReasoningEffort high` 覆盖 preset。
  - `codex` 命令参数包含 `-c model_reasoning_effort="..."`。
  - `claude` 和 `opencode` 命令构造符合预期。
  - 缺失 agent CLI 返回非零结果和中文错误。
  - `DryRun` 不调用真实 agent。

不测试真实网络调用，不依赖真实 API key。外部 CLI 用可注入命令构造函数、mock 可执行文件或 dry-run 结果验证。

## Verification

实现完成后需要执行：

```powershell
pnpm qa
pnpm test:pwsh:all
```

因为改动涉及 `scripts/pwsh/**`、`psutils/**`、`tests/**/*.ps1` 和根目录安装脚本逻辑。若本机 Docker 不可用，至少执行 `pnpm test:pwsh:full`，并在交付说明中明确 Linux 覆盖依赖 CI 或 WSL。

## Open Questions

当前设计没有未决问题。第一版目录名、公开命令名、首批 agent、prompt preset 格式、配置优先级和 README 范围均已确定。
