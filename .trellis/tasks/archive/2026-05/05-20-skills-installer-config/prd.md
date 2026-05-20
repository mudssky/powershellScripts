# brainstorm: skills 安装脚本

## Goal

在 `ai/skills` 下新增一个可配置的 skills 安装工具，方便在多台设备上同步和安装 AI skills。工具应复用项目里的 PowerShell 配置文件模块，并预期支持从 `vercel-labs/skills` 安装 skill。

## What I already know

* 需要研究 skills 安装问题，而不是直接拍脑袋实现。
* 目标目录是 `ai/skills`。
* 安装脚本需要支持配置文件。
* 配置加载应复用项目里的 `psutils/src/config` / `psutils/modules/config.psm1`，不要新增一套 parser。
* 预计安装来源包括 GitHub 仓库 `vercel-labs/skills`。
* `ai/skills` 下还需要一个目录用于存放个人本地开发的 skill。
* 需要制定一份通用 skill 规范，让开发完的 skill 可以给多个 agent 使用。
* 初步调研显示 `vercel-labs/skills` 是安装 CLI；实际安装示例通常面向 `vercel-labs/agent-skills` 或其他含 `SKILL.md` 的来源。
* `skills` CLI 已有 lock 文件：global 使用 `~/.agents/.skill-lock.json`，project 使用项目根 `skills-lock.json`。
* 初始配置文件应包含 `vercel-labs/agent-browser` 与 `supabase/agent-skills` 两个来源。

## Assumptions (temporary)

* 工具会用 PowerShell 编写，放在 `ai/skills` 附近，便于跨 Windows / Linux / macOS 使用。
* 配置文件会声明来源仓库、要安装的 skill 列表、目标目录和覆盖策略。
* 首版应优先做幂等安装和 dry-run，而不是完整的 skill registry 管理系统。
* 本地开发目录暂命名为 `ai/skills/dev`，安装配置与安装器放在同一棵 `ai/skills` 目录下。
* 通用 skill 规范以 `SKILL.md` + 可选 `references/`、`examples/`、`scripts/` 为核心结构，并避免写死单一 agent 的私有字段。

## Open Questions

* 第二轮如何拆分 config helper 与更多大文件重构子任务？

## Requirements (evolving)

* 在 `ai/skills` 下提供 skills 安装脚本和配置示例。
* 在 `ai/skills` 下提供个人本地开发 skill 的目录。
* 在 `ai/skills` 下提供通用 skill 编写规范，约束 `SKILL.md` frontmatter、目录结构、资源组织和跨 agent 兼容边界。
* 支持从配置文件读取安装目标。
* 复用现有 PowerShell 配置解析模块加载 env、JSON、`.psd1` 或 CLI 覆盖参数。
* 支持通过 `vercel-labs/skills` CLI 安装远程或本地 skill 来源。
* 支持从本地开发目录安装 skill 到多个 agent；本地开发 skill 也应走 `skills` CLI 安装路径，而不是独立 copy-only 安装路径。
* 安装计划应能把本地开发目录转换为 `npx skills add <local-path> --agent <agent>` 形式。
* 默认只安装配置文件显式列出的本地开发 skill。
* 执行脚本提供 `-IncludeDevAll` 参数，临时扫描 `ai/skills/dev/*/SKILL.md` 并把全部有效本地 skill 纳入安装计划。
* 配置文件应能声明安装作用域：global 或 project，并转换为 `skills` CLI 对应参数。
* 顶层 `scope` 是默认作用域；每个 skill 项可以覆盖 `scope`。
* `scope: project` 可配置 `projectPath`；未配置时默认使用当前仓库根目录。
* 如果 skill 项或顶层 `projectPath` 都未指定，且无法解析当前仓库根目录，project 安装应报错，不应静默回退 global。
* 若没有显式声明任何 scope，默认作用域为 global。
* 每个 skill 项应支持 `description` 字段，用于简要描述技能作用，并在 dry-run / install plan 中展示。
* 每个 skill 项应支持附带命令配置，用于安装 skill 所需的额外 CLI 或依赖，例如 Playwright skill 安装后执行浏览器/CLI 安装命令。
* 附带命令默认不静默执行，必须进入安装计划、日志和 ShouldProcess 确认链路。
* 配置应支持非 `skills add` 类型的工具安装/配置步骤，例如 Context7 官方安装方式 `npx ctx7 setup`。
* 工具安装步骤应与 skill 安装分开建模，避免把带认证/配置副作用的工具 setup 伪装成普通 skill。
* 初始配置应包含 Context7 setup 示例，默认以 CLI + Skills 模式配置 Claude；其他 agent 可由脚本参数或配置覆盖。
* tool setup 应支持 `check` 配置；执行前先检查是否已安装/已配置，已满足时在计划中标记 installed 并跳过 setup。
* Context7 的默认检测方式使用 `npx ctx7@latest skills list --claude` 或对应目标 agent 的 list 命令，而不是猜测文件路径。
* 配置文件格式使用 JSON，默认配置路径为 `ai/skills/skills.config.json`。
* 配置结构应参考 `skills` CLI lock 文件格式，但只表达期望状态；安装后的 hash/time/dismissed/lastSelectedAgents 等状态信息不进入项目配置。
* 配置文件应能声明默认安装 agent；默认值为 Claude + Codex。
* 运行脚本时应支持用参数统一覆盖配置中的默认 agent 列表。
* 配置中可以使用友好 agent 名称；`claude` 应映射到 `skills` CLI 的 `claude-code`，`codex` 直接映射到 `codex`。
* 首版动作只实现 install 与 dry-run，不单独实现 list / validate。
* install 前必须先生成安装计划；通过 `skills` CLI 安装的 skill 不额外实现安装前 check，是否已安装/覆盖由 `skills` CLI 与其 lock 机制负责。
* 非 `skills add` 类型的 tool setup 可通过显式 `check` 配置判断是否已配置，例如 Context7。
* dry-run 必须展示每个 skill 的目标来源、scope、agent 和将执行的命令；tool setup 若声明 check，应展示 check/setup 关系。
* 真实 install 默认在执行前展示计划并请求确认；`-Yes` 参数可跳过确认，用于自动同步。
* 脚本入口应使用 `[CmdletBinding(SupportsShouldProcess = $true)]`，支持 PowerShell 原生 `-WhatIf` 和 `-Confirm`。
* 对 `skills` CLI 安装项不做自定义“已安装后是否更新”提示；传入 `-Force` 时只表达为继续执行安装命令的显式意图。
* 真实安装时应保存 `skills` CLI 的 stdout/stderr 到日志文件，同时保留控制台输出。
* 日志实现采用脚本内轻量 helper，不为 MVP 新增通用日志模块。
* 内部消息优先使用 PowerShell streams；外部 `npx skills` 调用通过日志 helper 保留命令、参数、退出码和输出。
* 默认日志目录固定为 `ai/skills/logs/`，执行脚本可通过 `-LogDirectory` 覆盖；配置文件不提供日志目录字段。
* 初始 `skills.config.json` 示例应包含 `agent-browser` 和 `supabase-postgres-best-practices`。
* `ai/skills/Install-Skills.ps1` 不应继续作为超大单文件增长；应先评估并提取通用职责，降低入口脚本复杂度。
* `psutils` 只抽通用基础设施，不接收 skills 安装器领域语义。
* 第一轮只抽外部命令执行与轻量命令日志这类边界清晰的通用基础设施。
* config helper、配置路径/env placeholder 解析以及更多大文件拆分子任务放到第二轮，不进入第一轮实现范围。
* agent skill 目录解析、skills 已安装检测、ctx7 默认检查、安装计划领域模型属于 skills 安装器语义，应留在 `ai/skills` 私有模块。
* 如果某些逻辑只服务 skills 安装器的配置模型或计划生成，应拆到 `ai/skills` 私有模块，而不是污染 `psutils` 公共 API。
* 重构后 `Install-Skills.ps1` 应保留 CLI 入口、参数绑定、配置装配和高层流程，具体实现委托模块函数。
* 仓库中 500 行以上 PowerShell 文件较多；重构方案应参考已有 source-first / bundle 先例，而不是只针对单个文件做临时拆分。

## Acceptance Criteria (evolving)

* [ ] 可以通过配置文件声明至少一个远程 skill 来源并安装到本机目标目录。
* [ ] 初始配置包含 `vercel-labs/agent-browser` 与 `supabase/agent-skills`，并能生成对应安装计划。
* [ ] 可以通过配置文件声明至少一个本地开发 skill，并安装到多个 agent。
* [ ] 未传 `-IncludeDevAll` 时只安装显式配置项；传入后自动发现 `ai/skills/dev` 下所有包含 `SKILL.md` 的 skill。
* [ ] 配置文件示例使用 JSON，并能通过共享 `JsonFile` source 加载。
* [ ] 可以通过顶层配置和每个 skill 项切换 global/project 安装作用域。
* [ ] project scope 未显式配置 projectPath 时默认使用当前仓库根目录；无法解析时抛出明确错误。
* [ ] 配置中的 `description` 在 dry-run / install plan 中展示。
* [ ] 配置中的附带命令能在 skill 安装前或安装后执行，并受 dry-run / WhatIf / Confirm / Yes 控制。
* [ ] 附带命令失败时当前 skill 标记失败，并停止或按策略跳过后续步骤。
* [ ] 配置可以声明 `ctx7` 这类 tool setup，dry-run 展示命令，真实执行走 ShouldProcess 和日志。
* [ ] tool setup 支持 check 命令；ctx7 check 可通过 `ctx7 skills list` 判断是否已安装对应 skill。
* [ ] `skills` CLI 安装项不读取官方 lock 做额外状态判断；安装器只生成计划并委托 `npx skills add` 执行。
* [ ] 未显式配置 agent 时默认安装到 Claude + Codex；执行脚本时可以覆盖为其他 agent。
* [ ] 安装脚本支持 dry-run，能展示将安装/跳过/覆盖的 skill。
* [ ] 真实安装前提示用户确认完整计划；传入 `-Yes` 时非交互执行。
* [ ] 支持 `-WhatIf` / `-Confirm`，并在调用 `npx skills add` 前经过 `ShouldProcess`。
* [ ] `-Force` 可用于在已安装或未知状态下明确继续执行安装命令。
* [ ] 真实安装生成日志文件，记录安装计划、执行命令、stdout/stderr 和退出码。
* [ ] 默认日志写入 `ai/skills/logs/`，且 `-LogDirectory` 能覆盖本次执行日志目录。
* [ ] `ai/skills` 下存在本地开发目录和通用 skill 规范文档。
* [ ] 缺失配置、重复 skill、网络/下载失败等错误有明确提示。
* [ ] 配置加载使用 `psutils/modules/config.psm1` 暴露的共享解析器。
* [ ] 有 Pester 测试覆盖配置解析、安装计划生成和幂等行为。
* [ ] 有 Pester 测试覆盖安装计划生成、tool check 计划、dry-run/WhatIf 不执行外部命令。
* [ ] `Install-Skills.ps1` 的入口文件行数显著降低，核心业务逻辑拆入可测试模块。
* [ ] 被抽入 `psutils` 的函数必须有稳定公共命名、中文帮助注释、参数/返回说明和对应 Pester 测试。
* [ ] skills 私有模块与 `psutils` 公共模块职责边界清晰：通用基础设施进 `psutils`，安装器领域模型留在 `ai/skills`。
* [ ] 当前已安装检测行为保持不变：任一目标 agent 目录存在对应 skill 时跳过，两个都没有时才进入待执行计划。

## Definition of Done (team quality bar)

* Tests added/updated (unit/integration where appropriate)
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* 暂不实现在线 marketplace UI。
* 暂不自动推送或同步用户私有 skill 内容到远程。

## Technical Notes

* 需要检查 `ai/skills` 是否已存在相近脚本或配置。
* 需要检查 `psutils/src/config` 的配置来源能力与最近补充的 Trellis 规范。
* 需要研究 `vercel-labs/skills` 仓库结构和安装约定。
* 仓库已有 `ai/coding/claude/Manage-ClaudeSkills.ps1`，但它偏 Claude 本地开发/同步，且手写 frontmatter 解析；新工具应抽象到 `ai/skills`，并复用共享配置模块。
* `vercel-labs/skills` 的 Context7 文档显示支持 `npx skills add <source>`、`--agent`、`-g`、`-y` 和本地路径来源。
* Context7 文档显示 `skills-lock.json` 是 project-local lock，`~/.agents/.skill-lock.json` 是 global lock；但 lock 内包含安装状态字段，不适合作为本仓库手写配置。

## Decision (ADR-lite, evolving)

**Context**: 远程仓库 skill 和个人本地开发 skill 都需要同步到多个 agent。如果分别实现远程 CLI 安装和本地 copy 安装，行为、错误处理和 agent 目录探测会漂移。

**Decision**: MVP 统一包装 `vercel-labs/skills` CLI。远程来源使用 `npx skills add <repo-or-url>`；本地开发 skill 使用 `npx skills add ./ai/skills/dev/<skill-name>`。

**Consequences**: 实现可以复用 `skills` CLI 的 agent 探测和安装语义，但运行时依赖 Node/npm 可用。纯 PowerShell copy/link 可作为未来离线 fallback，而不是首版主路径。

### Decision: JSON configuration

**Context**: 配置需要跨多台设备同步，且要和项目现有 PowerShell 配置加载规范对齐。

**Decision**: MVP 只支持 JSON 配置文件，默认路径为 `ai/skills/skills.config.json`。配置结构参考 `skills` CLI lock 文件，以 skill 名作为 key，包含 `source`、`sourceType`、可选 `sourceUrl`、`skillPath`、`pluginName` 和 per-skill `agents`，但只保存期望状态。

**Consequences**: 配置加载可以直接复用 `Resolve-ConfigSources` 的 `JsonFile` source；`.psd1` 或其他格式可作为未来扩展，不进入首版。配置文件不是官方 lock 的替代品，不手写 `skillFolderHash`、`installedAt`、`updatedAt`、`dismissed` 或 `lastSelectedAgents`。

### Decision: delegate installed-state handling to skills CLI

**Context**: `skills` CLI 已经维护 global 和 project lock，且安装命令能基于它自己的状态处理重复安装/覆盖语义。项目配置只需要表达期望安装项，不应该复制 CLI 的状态机。

**Decision**: 对通过 `npx skills add` 安装的 skill，安装器不读取官方 lock，也不调用 `skills list` 做额外 check。安装器负责生成计划、确认、日志和参数映射；安装状态与 lock 更新全部委托 `skills` CLI。

**Consequences**: 脚本不会自行计算或写入 hash，也不会把官方 lock 当成配置模板提交。同步体验依赖 `skills` CLI 的幂等行为；如果未来发现 CLI 对重复安装体验不足，再补一个可选 `status` 子命令而不是默认安装前 check。

### Decision: per-skill scope override

**Context**: 有些 skill 适合作为全局个人能力安装，有些 skill 只应该在某个项目中生效。顶层 scope 简化常见配置，但不能限制单项覆盖。

**Decision**: 配置支持顶层默认 `scope`，每个 skill 项可以覆盖 `scope` 和 `projectPath`。未声明 scope 时默认为 global。project scope 未声明 `projectPath` 时使用当前仓库根目录；无法解析项目根时抛错。

**Consequences**: 同一份配置可以同时管理 global 和 project skills。脚本需要按目标 projectPath 分组执行 `npx skills add`，并在对应目录下读取 project lock / 调用 project 安装。

### Decision: per-skill description and commands

**Context**: 有些 skill 不只是提示词/文档，还依赖额外 CLI 或环境准备，例如 Playwright 相关 skill 可能需要安装浏览器或 CLI。配置也需要给人一个简短摘要，方便 dry-run 时判断用途。

**Decision**: 每个 skill 项支持 `description` 和 `commands`。`description` 只用于展示和日志；`commands` 是显式配置的附带命令，纳入安装计划，并受 dry-run、WhatIf、Confirm、Yes 和日志机制约束。

**Consequences**: 配置能表达完整的本机准备步骤，但命令执行属于高风险操作，必须默认可见、可预览、可确认。首版不从远程 skill 自动推断命令，只执行本地配置显式声明的命令。

### Decision: separate tool setup from skill install

**Context**: Context7 的官方安装方式是 `npx ctx7 setup`，会处理认证、API key、agent skill 或 MCP 配置。它不是普通 `npx skills add <source>` 安装项。

**Decision**: 配置增加 `tools` 区域，用于声明带副作用的工具 setup。`skills` 区域只表达通过 `skills` CLI 安装的 skill；`tools` 区域表达 `ctx7`、Playwright 这类额外工具安装/配置命令。

**Consequences**: 安装计划会分成 tool setup 和 skill install 两类步骤，两者都支持 dry-run、WhatIf、Confirm、Yes 和日志。Context7 这类命令可以按官方方式执行，不需要伪装成 skill。

### Decision: tool setup checks support directory probes and explicit commands

**Context**: 不同工具的安装完成信号不一样。Context7 的 `skills list` 输出在已存在本地 skill 目录时仍可能显示 `No skills installed`，单纯依赖 CLI list 不稳定。普通 skill 安装也需要避免每次计划展示都列出已存在项。

**Decision**: `tools` 项支持目录型 check 和命令型 check。目录型 check 根据配置中的 agent 和 skill 名称检查 Claude/Codex skill 目录；命令型 check 作为可选 fallback。Context7 默认使用目录型 check 检测 `find-docs`。

**Consequences**: tool 检测逻辑仍由配置声明，不把 ctx7 写死到流程里；同时避免不可靠 CLI list 导致重复 setup。新增 agent 目录解析能力后，需要评估是否抽到 `psutils` 供其他脚本复用。

### Decision: explicit local skills by default

**Context**: 本地开发目录会包含草稿、实验或尚未稳定的 skill。默认全量安装可能污染多个 agent 的运行环境。

**Decision**: 默认只安装配置文件显式列出的本地 skill；脚本提供 `-IncludeDevAll` 作为临时全量同步开关，只自动发现包含 `SKILL.md` 的一级子目录。

**Consequences**: 日常同步保持可复现；需要快速刷新全部本地开发 skill 时仍有一条短路径。

### Decision: install and dry-run only for MVP

**Context**: 用户主要目标是多设备同步安装 skills。单独的 list / validate 可以提高管理体验，但会扩大首版分支和测试面。

**Decision**: 首版只实现 install 与 dry-run。dry-run 承担配置校验、安装计划展示和已安装状态预览；install 在执行前复用同一套计划并提示确认。

**Consequences**: MVP 保持聚焦，但仍能在安装前发现明显配置和状态问题。未来可以把同一套计划生成逻辑拆成独立 list / validate 命令。

### Decision: use PowerShell ShouldProcess

**Context**: 安装 skill 会修改本机 agent 配置目录，且可能覆盖已安装内容。PowerShell 已有标准确认/预览机制。

**Decision**: 安装脚本使用 `SupportsShouldProcess`。`-DryRun` 展示安装计划；`-WhatIf` 走 PowerShell 原生预览；真实执行在调用 `npx skills add` 前经过 `ShouldProcess`。

**Consequences**: 行为符合 PowerShell 用户预期，测试也可以通过 `-WhatIf` 验证不会执行外部命令。`-Yes` 用于跳过脚本级计划确认，`-Force` 用于允许更新/覆盖已安装 skill。

### Decision: lightweight log wrapper

**Context**: `npx skills add` 是外部命令，安装失败时需要保留 stdout/stderr 和退出码，方便多设备同步排障。PowerShell `Start-Transcript` 适合整段会话录制，但不够适合作为安装器的结构化日志主路径。

**Decision**: MVP 在安装脚本内实现轻量日志 helper。内部消息使用 PowerShell streams；外部命令通过 helper 同步输出到控制台和日志文件，并记录退出码。

**Consequences**: 初版实现已快速落地，但随着安装器增长到仓库最大 PowerShell 单文件，轻量日志和外部命令执行 helper 需要重新评估是否抽入 `psutils`。如果抽入公共模块，应保持 API 小而稳定，避免把 skills 安装器领域概念带入通用层。

### Evidence: large PowerShell files

当前仓库 `.ps1` / `.psm1` 共 246 个文件，平均约 173 行；500 行以上文件 19 个，其中 1000 行以上 5 个。最大文件包括：

| Lines | Path | Notes |
|---:|---|---|
| 1609 | `ai/skills/Install-Skills.ps1` | 当前最大，且不是生成 bundle |
| 1477 | `scripts/pwsh/devops/Postgres-Toolkit.ps1` | 单文件分发产物；源码已拆到 `scripts/pwsh/devops/postgresql/**` |
| 1220 | `psutils/modules/oss.psm1` | psutils 公共模块 |
| 1173 | `scripts/pwsh/devops/start-container.ps1` | 独立运维脚本 |
| 1016 | `scripts/pwsh/download/Install-GitHubCli.ps1` | 独立下载安装器 |
| 982 | `psutils/modules/help.psm1` | psutils 公共模块 |
| 808 | `config/service/oss/rclone/rclone-ops.ps1` | 配置域脚本 |
| 682 | `psutils/modules/filesystem.psm1` | psutils 公共模块 |
| 619 | `psutils/modules/env.psm1` | psutils 公共模块 |
| 600 | `psutils/modules/cache.psm1` | psutils 公共模块 |

结论：大文件问题不是孤例，但 `Postgres-Toolkit` 已提供可借鉴模式：可维护源码拆分，必要时再生成单文件分发产物。`Install-Skills.ps1` 更适合先拆可测试模块；是否保留单文件入口或生成 bundle 需要单独决策。

### Cross-file extraction candidates

横向扫描 500 行以上 PowerShell 文件后，优先候选如下：

| Candidate | Evidence | Proposed Home | Notes |
|---|---|---|---|
| Native command execution wrapper | `Install-Skills.ps1` 有 `Invoke-SkillsExternalCommand` / `Resolve-SkillsExecutablePath` / `Format-SkillsCommandLine`；`rclone-ops.ps1` 有 `Invoke-RcloneOpsProcess`；PostgreSQL toolkit 有 `Invoke-PgNativeCommand`；agent runner 有 `Invoke-AiAgentNativeCommand` | `psutils/modules/process.psm1` 或 `psutils/modules/command.psm1` | 最高优先级。公共 API 应只表达 `FilePath`、`ArgumentList`、`WorkingDirectory`、`Environment`、`AllowFailure`、`SuppressOutput`、`LogPath`，不要包含 skills 语义。 |
| Lightweight run log helper | `Install-Skills.ps1` 自带 `New-SkillsLogFile` / `Write-SkillsLogLine`；Postgres toolkit 有 `Write-PostgresToolkitMessage`；AHK build 有 `Write-BuildLog` | 可并入 `process.psm1`，或独立 `psutils/modules/logging.psm1` | 保持简单行日志即可，不引入完整日志框架。若只服务 native command，可先放进 process module。 |
| Config object helpers | `Install-Skills.ps1`、`Install-GitHubCli.ps1`、`rclone-ops.ps1` 都有 `ConvertTo-*Hashtable` / `Get-*ConfigValue`；`psutils/src/config` 已有 `ConvertTo-ConfigHashtable` 但未作为清晰公共工具使用 | 第二轮扩展 `psutils/modules/config.psm1` | 不进入第一轮。可以公开/补强大小写不敏感读取、浅层 hashtable 转换、可选 nested value。 |
| Config path/env placeholder expansion | `Install-Skills.ps1` 与 `Install-GitHubCli.ps1` 都有 `Resolve-*EnvPlaceholder` / `Resolve-*Path`；`rclone-ops.ps1` 有 `${VAR}` 展开 | 第二轮扩展 config 或新增 path 模块 | 不进入第一轮。适合抽“配置路径解析”：`~`、`${VAR}`、`%VAR%`、相对 base path、缺失 env 抛错。 |
| Plan/confirmation prompt | `Install-Skills.ps1` 当前有计划确认；部分脚本有 `ShouldProcess` / `Read-Host` / fzf 选择 | 暂不优先抽 | 交互文案和计划结构领域差异较大；先保留在调用方，仅复用 PowerShell 原生 `ShouldProcess`。 |
| Installed-state probes | `Test-ApplicationInstalled`、`Test-ModuleInstalled` 已在 `psutils`；skills 目录检查是 agent-specific | 部分保留现状 | 通用“命令是否存在/模块是否安装”已有；Claude/Codex skill 目录检查留在 `ai/skills` 私有模块。 |

暂不建议抽取：

* `psutils/modules/oss.psm1` 的 OSS 签名/HTTP 逻辑：虽大但领域内聚。
* `psutils/modules/help.psm1` 的帮助搜索：虽大但已是单一公共模块。
* `Sync-ClaudeConfig.ps1` 的 manifest merge / symlink 逻辑：Claude 配置领域语义强。
* Docker、Tailscale、rclone 的命令编排本体：可以复用 native command wrapper，但业务流程不进 `psutils`。

### Decision: psutils extraction boundary

**Context**: `Install-Skills.ps1` 已成为仓库最大的 PowerShell 单文件，但横向扫描显示多个 500+ 行脚本都存在基础设施重复。抽象边界如果过宽，会把 skills、Docker、rclone、Claude 等业务概念污染到 `psutils`；如果过窄，则只能局部瘦身，无法改善后续脚本复用。

**Decision**: `psutils` 只抽通用基础设施。第一轮只抽外部命令执行 wrapper 与轻量命令日志。配置对象读取 helper、配置路径/env placeholder 解析以及更多大文件拆分子任务放到第二轮。skills 安装计划、Claude/Codex skill 目录、ctx7 默认检查、agent 名称映射等领域语义留在 `ai/skills` 私有模块。

**Consequences**: 第一轮先把 `Install-Skills.ps1` 的外部命令与日志能力替换为 `psutils` 公共 API，并保留配置 helper 的本地实现。`psutils` API 必须保持小而稳定，新增函数需要 Pester 覆盖和模块导出；调用方仍负责业务计划、文案和确认流程。第二轮再评估 config helper 与更多大文件拆分。

### Decision: fixed default log directory

**Context**: 日志需要易找且不污染同步配置。多设备同步时，日志目录属于本机运行产物，不应写入配置文件。

**Decision**: 默认写入 `ai/skills/logs/`，执行时可用 `-LogDirectory` 覆盖。配置文件不包含日志字段。

**Consequences**: 配置保持聚焦于安装来源、scope 和 agent；日志路径仍可在 CI 或临时排障场景中覆盖。

## Configuration Model (evolving)

推荐配置形状：

```json
{
  "version": 1,
  "scope": "global",
  "agents": ["claude", "codex"],
  "tools": {
    "ctx7": {
      "description": "安装并配置 Context7 文档检索能力",
      "phase": "preInstall",
      "check": {
        "command": "npx",
        "args": ["ctx7@latest", "skills", "list", "--claude"],
        "contains": "context7"
      },
      "command": "npx",
      "args": ["ctx7@latest", "setup", "--cli", "--claude"]
    }
  },
  "skills": {
    "agent-browser": {
      "description": "浏览器自动化与网页/桌面应用交互 skill",
      "source": "vercel-labs/agent-browser",
      "sourceType": "github",
      "sourceUrl": "https://github.com/vercel-labs/agent-browser.git",
      "skillPath": "skills/agent-browser/SKILL.md"
    },
    "supabase-postgres-best-practices": {
      "description": "Supabase Postgres 查询、schema 与性能优化最佳实践",
      "source": "supabase/agent-skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/supabase/agent-skills.git",
      "skillPath": "skills/supabase-postgres-best-practices/SKILL.md",
      "pluginName": "postgres-best-practices"
    },
    "my-local-skill": {
      "description": "个人本地开发的通用 skill 示例",
      "source": "./dev/my-local-skill",
      "sourceType": "local",
      "scope": "project",
      "projectPath": ".",
      "agents": ["claude"],
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
}
```

脚本覆盖示例：

```powershell
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Agent codex,opencode
```

覆盖后本次执行所有 skill 都使用 CLI 参数给出的 agent 列表；配置文件内容不被改写。

## Research References

* [`research/skills-cli-and-repo-structure.md`](research/skills-cli-and-repo-structure.md) — `vercel-labs/skills` 是 CLI 安装工具，适合作为远程/本地 skill 安装后端。
* [`research/powershell-logging.md`](research/powershell-logging.md) — PowerShell 日志建议使用 streams + 外部命令轻量日志 helper。
* [`research/skills-lock-format.md`](research/skills-lock-format.md) — `skills` CLI 已有 global/local lock，配置应贴近其结构但不替代官方 lock。
