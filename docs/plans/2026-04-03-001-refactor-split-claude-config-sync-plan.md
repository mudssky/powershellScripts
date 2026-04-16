---
title: refactor: split claude config sync sources
type: refactor
status: active
date: 2026-04-03
origin: docs/brainstorms/2026-04-03-claude-settings-split-brainstorm.md
---

# refactor: split claude config sync sources

## Overview

本计划承接 `docs/brainstorms/2026-04-03-claude-settings-split-brainstorm.md`，目标是把当前 `ai/coding/claude/Sync-ClaudeConfig.ps1` 的“整目录软链接”模式重构为“共享模板 + 本机覆盖 + 生成结果”的两层配置模型。

这次不是单纯移动一个 `settings.json` 文件，而是同时完成三件事：

1. 把可提交的 Claude 默认配置从当前已跟踪的 `ai/coding/claude/.claude/settings.json` 中拆出来，形成明确的共享模板。
2. 把本机 secrets、provider 差异和个人偏好固定到 `settings.local.json`，不再让仓库承担这些内容。
3. 把 `Sync-ClaudeConfig.ps1` 改成确定性的生成器和白名单同步器，停止把整个 `ai/coding/claude/.claude` 暴露为 `~/.claude` 的真实运行目录。

计划的终态是：`~/.claude/settings.json` 成为纯生成产物，`ai/coding/claude/.claude` 只保留共享资产，运行态历史/缓存/调试数据回到真正的用户目录中（see origin: `docs/brainstorms/2026-04-03-claude-settings-split-brainstorm.md`）。

## Problem Frame

当前仓库把 `ai/coding/claude/.claude` 同时当成“可提交配置目录”和“用户真实运行目录”使用，导致两个问题叠在一起：

- 已跟踪的 `ai/coding/claude/.claude/settings.json` 可能直接承载 `ANTHROPIC_API_KEY`、`ANTHROPIC_BASE_URL` 等敏感配置。
- `backup`、`history`、`debug`、`sessions`、`transcripts` 等运行态内容被迫依赖黑名单 `.gitignore` 来防漏，而不是通过明确目录边界来避免进入仓库。

origin brainstorm 已经把产品侧边界定清楚了：首版不引入 profile 层，保留“两层配置”；`env` 拆成“共享默认值 + 本机敏感覆盖”；`settings.local.json` 采用按键级深度合并；`~/.claude/settings.json` 是纯生成产物，sync 可以直接覆盖（see origin: `docs/brainstorms/2026-04-03-claude-settings-split-brainstorm.md`）。

planning 的任务是把这些边界转成可执行的文件结构、迁移策略、测试面和文档更新方案，同时尽量复用仓库已有模式，而不是发明一套新的 dotfiles 框架。

## Requirements Trace

- R1. 共享模板中不得出现真实 secrets；`ANTHROPIC_API_KEY` 一类字段必须迁出可提交源。
- R2. 仓库必须保留一份可提交、可审阅、可复制的 Claude 默认配置模板。
- R3. 本机私有配置必须通过 `settings.local.json` 参与最终配置生成。
- R4. `Sync-ClaudeConfig.ps1` 需要从整目录软链接转成“白名单同步 + 生成最终 settings”。
- R5. 运行态目录必须与共享资产脱钩，不再依赖黑名单作为主边界。
- R6. router 与直连两类 provider 场景都必须能通过 local 覆盖完成。
- R7. 用户必须容易判断该改模板文件还是 local 文件。
- R8. 同步前需要最少一层 secrets guardrail，阻止明显密钥进入模板。
- R9. 新结构应继续复用仓库现有 `*.local.json` 约定。
- R10. `settings.local.json` 必须支持按键级局部覆盖与深度合并。
- R11. `~/.claude/settings.json` 必须是可重建、可覆盖的纯生成产物。

## Scope Boundaries

- 首版不引入 `profiles/` 目录或 provider profile 切换层；router / 直连差异全部通过 `settings.local.json` 表达。
- 首版不把系统密码管理器、1Password、gopass、sops 等更重的密钥管理系统纳入方案。
- 首版不支持通过 local 覆盖显式“删除”共享模板中的键；覆盖能力以新增与覆盖为主，不为罕见的删除语义增加额外复杂度。
- 首版不新增 pre-commit secret hook；强制 guardrail 先落在 `Sync-ClaudeConfig.ps1` 上。
- 首版不重构所有 Claude 相关文档，只更新直接描述当前同步方式、设置来源和使用入口的文档。

## Context & Research

### Relevant Code and Patterns

- `ai/coding/claude/Sync-ClaudeConfig.ps1` 当前直接把 `ai/coding/claude/.claude` 链接到 `~/.claude`，这是需要拆开的主入口。
- `ai/coding/claude/.gitignore` 当前通过黑名单排除 `.claude/debug`、`.claude/transcripts`、`.claude/sessions` 等运行态目录，说明仓库已经在被动应对目录混杂问题。
- `ai/coding/claude/config/user.settings.json` 已经提供了一份不含 secrets 的安全设置模板，说明“模板入库、真实凭据本机保存”在仓库里并不是全新的模式。
- `config/gemini-cli/Apply-GeminiCliConfig.ps1` 展示了同仓库内“从 repo 配置复制到用户主目录”的简单脚本模式，可作为用户目录目标路径与跨平台 home 解析的参考。
- `tests/Sync-PathFromBash.Tests.ps1` 与 `tests/Manage-BinScripts.Tests.ps1` 展示了当前仓库对脚本级行为测试的模式：临时目录 + 子进程 + 明确的用户可见行为断言。
- 当前跟踪的 `ai/coding/claude/.claude` 共享资产主要包括 `CLAUDE.md`、`commands/`、`output-styles/`、`skills/`、`ccline/` 和 `config.json`；计划需要保留这些资产的同步能力，但不再把 `settings.json` 视为共享资产的一部分。

### Institutional Learnings

- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md` 说明脚本级工作流改动不能只改命令本体，命令、文档和边界说明需要一起更新，否则语义会重新漂移。
- 同一份 solution 还强调了外部环境依赖与重型行为应通过可控 seam 测试，而不是假设宿主环境天然满足；这适用于 symlink 迁移、home 目录切换和 JSON merge 行为的脚本测试设计。

### External References

- Anthropic Claude Code settings 文档说明了官方的设置层级与 `.claude/settings.local.json` 作为本地覆盖层的定位，并给出了对象深合并、数组拼接去重、标量覆盖的继承语义：<https://docs.anthropic.com/en/docs/claude-code/settings>

## Key Technical Decisions

- **共享模板文件迁移到 `ai/coding/claude/config/settings.json`，不再保留已跟踪的 `ai/coding/claude/.claude/settings.json`。**  
  理由：`config/` 目录更符合仓库现有“配置模板源”的组织方式，也能避免把“共享资产目录”和“配置源文件”继续混在同一个 `.claude/` 目录里。现有 `ai/coding/claude/config/user.settings.json` 作为安全模板的前身，应迁移为新的 canonical shared settings 文件。

- **本机覆盖文件固定为 `ai/coding/claude/config/settings.local.json`，并继续依赖仓库现有 `*.local.json` 忽略规则。**  
  理由：这样既复用仓库约定，也能把 local 文件放在模板旁边，避免用户在运行态目录里再找一份“真正要改的文件”。

- **`ai/coding/claude/config/settings.local.json` 是 optional local layer，缺失时仍允许 shared template 单独生成最终配置。**  
  理由：有些场景会把 secrets 交给外部环境变量或暂时只需要共享默认值；脚本不应把“没有 local 文件”直接视为错误。

- **最终 `~/.claude/settings.json` 通过“共享模板 + local 覆盖”在内存中合并后整文件写出，而不是基于已有全局文件再增量 merge。**  
  理由：目标文件已经被定义为纯生成产物；直接写出完整对象最能避免漂移、手改残留和优先级混乱。

- **自定义 merge 语义对齐 Claude 官方继承直觉：标量覆盖、对象深合并、数组拼接去重。**  
  理由：用户已经接受“按键级局部覆盖”的模型，而尽量贴近 Claude 官方继承语义可以降低认知偏差，避免 local 层的行为和官方设置层级相互打架。

- **settings merge 的删除语义首版不支持。**  
  理由：当前需求集中在补充 secrets、provider 差异和少量个人偏好，支持 `null` 删除或路径级排除会显著增加 merge 与验证复杂度，但没有明确当前用例支撑。

- **`Sync-ClaudeConfig.ps1` 改为白名单同步器，且只在受管路径内做覆盖或清理。**  
  理由：`~/.claude` 未来需要同时承载 managed assets 和运行态目录，脚本不能再把根目录视为可整体替换对象；受管路径应显式、可审阅、可测试。

- **guardrail 首版只强制检查共享模板，不检查 `settings.local.json`。**  
  理由：真正要防的是“把 secrets 提交进仓库”；对本机 local 做强约束意义不大，反而容易干扰用户正常保存本机敏感值。

- **保留 `Sync-ClaudeConfig.ps1` 作为入口脚本路径，不新增新的用户入口。**  
  理由：这次重构的主要价值在行为边界而不是命令命名；保持入口稳定可以降低迁移摩擦。

## Open Questions

### Resolved During Planning

- **共享模板放在 `ai/coding/claude/.claude/settings.json` 还是 `ai/coding/claude/config/settings.json`？**  
  结论：放在 `ai/coding/claude/config/settings.json`，让 `.claude/` 回归共享资产目录，避免继续混淆。

- **是否需要首版就引入 provider profile？**  
  结论：不需要。router / 直连场景先直接写在 `ai/coding/claude/config/settings.local.json` 中。

- **合并结果应该写回已有的 `~/.claude/settings.json`，还是整体重建？**  
  结论：整体重建；目标文件是纯生成产物，不再作为配置真源参与决策。

- **guardrail 应先落在哪一层？**  
  结论：首版仅放在 `ai/coding/claude/Sync-ClaudeConfig.ps1` 内，对共享模板执行阻断式检查；pre-commit hook 不纳入本轮范围。

### Deferred to Implementation

- **guardrail 的具体规则集**：例如是否只拦截 `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` 这类显式键，还是连 `sk-` / `Bearer ` 等值模式也一起覆盖，可在实现时基于误报成本微调。
- **受管白名单是否最终需要独立 manifest 文件**：首版计划允许直接在脚本中声明受管路径；如果后续路径继续增多，再决定是否抽成独立 JSON manifest。
- **backup 目录的最终命名与保留策略**：计划要求 first-run migration 前必须留出可恢复快照，但具体目录名与清理策略可以在实现阶段压实。

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
repo source of truth
├── ai/coding/claude/config/settings.json
├── ai/coding/claude/config/settings.local.json   (ignored, optional)
└── ai/coding/claude/.claude/                     (managed shared assets only)

Sync-ClaudeConfig.ps1
  -> detect current ~/.claude state
  -> if symlink-to-repo: backup + materialize real ~/.claude directory
  -> load shared settings
  -> load local settings if present
  -> validate shared template has no secrets
  -> merge settings (scalar override / object deep merge / array concat+dedup)
  -> write ~/.claude/settings.json atomically
  -> sync managed asset whitelist into ~/.claude
  -> leave runtime-only directories unmanaged

result
~/.claude/
├── settings.json            (generated)
├── output-styles/...        (managed sync)
├── commands/...             (managed sync)
└── history/debug/...        (runtime, unmanaged)
```

## Implementation Units

- [ ] **Unit 1: 重建 Claude 设置源文件边界**

**Goal:**  
把当前“共享模板”和“共享资产目录”拆开，确定后续 sync 的唯一输入文件位置，消除已跟踪 `ai/coding/claude/.claude/settings.json` 的角色冲突。

**Requirements:**  
R1, R2, R3, R7, R9

**Dependencies:**  
None

**Files:**
- Create: `ai/coding/claude/config/settings.json`
- Delete: `ai/coding/claude/.claude/settings.json`
- Delete: `ai/coding/claude/config/user.settings.json`

**Approach:**
- 以当前安全模板 `ai/coding/claude/config/user.settings.json` 为基础，生成新的 canonical shared template `ai/coding/claude/config/settings.json`。
- 从旧的 tracked `ai/coding/claude/.claude/settings.json` 中迁移所有仍然应该共享的非敏感默认值，特别是安全的 `env` 默认项、`permissions.defaultMode`、`enabledPlugins`、`statusLine`、`language`、`plansDirectory` 等。
- 不把 `ANTHROPIC_API_KEY`、`ANTHROPIC_BASE_URL` 或其他 provider-specific secrets 再写回共享模板。
- 明确 `ai/coding/claude/.claude/` 后续只保留被同步的共享资产，不再承载 settings 源文件。

**Patterns to follow:**
- `config/gemini-cli/Apply-GeminiCliConfig.ps1`
- `ai/coding/claude/config/user.settings.json`

**Test scenarios:**
- Test expectation: none -- 这是源文件布局与 tracked artifact 边界重整，行为验证在 `tests/Sync-ClaudeConfig.Tests.ps1` 中通过后续 sync 行为间接覆盖。

**Verification:**
- 仓库中不再存在已跟踪的 Claude settings secrets 入口。
- 新加入的贡献者能够通过 `ai/coding/claude/config/settings.json` 直接找到“共享默认配置”的单一来源。

- [ ] **Unit 2: 把 Sync 脚本改成确定性的 settings 生成器**

**Goal:**  
让 `ai/coding/claude/Sync-ClaudeConfig.ps1` 从整目录软链接脚本转成“读取 shared + local、生成最终 `~/.claude/settings.json`、迁移旧 symlink”的确定性生成器。

**Requirements:**  
R3, R4, R6, R10, R11

**Dependencies:**  
Unit 1

**Files:**
- Modify: `ai/coding/claude/Sync-ClaudeConfig.ps1`
- Test: `tests/Sync-ClaudeConfig.Tests.ps1`

**Approach:**
- 脚本启动时先检测 `~/.claude` 当前状态：不存在、真实目录、或旧的 symlink-to-repo。
- 如果发现 `~/.claude` 是旧 symlink，先生成一份 timestamped backup，再把 symlink 物化为真实目录，确保 repo 不再承担真实运行目录角色。
- `ai/coding/claude/config/settings.json` 始终作为 shared input；`ai/coding/claude/config/settings.local.json` 为 optional local input，存在时再参与 merge。
- 合并逻辑采用标量覆盖、对象深合并、数组拼接去重；首版不支持 local 通过删除语义移除 shared 键。
- 最终 settings 对象统一在内存中构建并完整写出到 `~/.claude/settings.json`，不再读取既有全局文件作为 merge 来源。
- 写入流程应先完成校验，再一次性替换目标文件，避免半写状态损坏最后生效配置。

**Patterns to follow:**
- `tests/Sync-PathFromBash.Tests.ps1`
- `tests/Manage-BinScripts.Tests.ps1`
- `config/gemini-cli/Apply-GeminiCliConfig.ps1`

**Test scenarios:**
- Happy path: shared template包含非敏感 `env` 默认值且 local 文件只覆盖 `env.ANTHROPIC_BASE_URL`、`env.ANTHROPIC_API_KEY` 时，生成的 `~/.claude/settings.json` 同时保留共享默认值与 local 差异。
- Happy path: local 文件只覆盖一个 `enabledPlugins.<name>` 或 `model` 键时，其余 shared settings 保持不变。
- Edge case: local 文件不存在时，脚本仍能用 shared template 单独生成 `~/.claude/settings.json`。
- Edge case: shared 与 local 都包含 `permissions.allow` 时，结果数组按拼接去重合并，而不是整段替换。
- Error path: local 文件 JSON 非法时，脚本在写入前失败，并保留原有 `~/.claude/settings.json`。
- Integration: `~/.claude` 为旧 symlink-to-repo 时，脚本会把它迁移成真实目录，同时保留原运行态内容和 managed assets。

**Verification:**
- 运行 sync 后，`~/.claude/settings.json` 的内容只取决于 shared template 与 local override。
- 旧的 symlink 工作流被安全终止，后续 Claude 运行态数据不再写回仓库目录。

- [ ] **Unit 3: 实现受管资产白名单同步与模板 guardrail**

**Goal:**  
把共享资产同步范围收敛到明确白名单，并在模板层增加 secrets guardrail，避免仓库再次回到“靠黑名单补洞”的状态。

**Requirements:**  
R4, R5, R8, R11

**Dependencies:**  
Unit 2

**Files:**
- Modify: `ai/coding/claude/Sync-ClaudeConfig.ps1`
- Modify: `ai/coding/claude/.gitignore`
- Test: `tests/Sync-ClaudeConfig.Tests.ps1`

**Approach:**
- 在脚本中声明受管共享资产路径集合，初始范围至少覆盖当前 tracked 的 `CLAUDE.md`、`commands/`、`output-styles/`、`skills/`、`ccline/`、`config.json`。
- sync 只在这些受管路径内做复制、更新和必要的 scoped prune；不在 `~/.claude` 根目录做全量删除，也不碰运行态路径。
- 共享模板写入前执行 guardrail：如果 `ai/coding/claude/config/settings.json` 中出现显式 secret 键或明显密钥值，脚本直接失败并拒绝覆盖 target。
- guardrail 只检查 shared template，不阻止 local 文件保存 secrets。
- 继续保留 `.gitignore` 作为兜底，但把它降级为“第二道保险”，而不是主隔离机制。

**Patterns to follow:**
- 当前 tracked shared assets 列表：`ai/coding/claude/.claude/**`
- `ai/coding/claude/.gitignore`

**Test scenarios:**
- Happy path: `ai/coding/claude/.claude/output-styles/engineer-professional.md` 等受管文件会同步到 `~/.claude` 对应位置。
- Edge case: `~/.claude/history.jsonl`、`~/.claude/sessions/` 等非受管运行态内容在 sync 后仍保留。
- Edge case: 受管目录中已删除的旧 shared asset 会在 target 的对应受管子目录中被清理，但不会波及其他非受管路径。
- Error path: shared template 中出现 `ANTHROPIC_API_KEY` 或明显 `sk-` 值时，脚本在写 target 前中止，并给出可行动的错误提示。
- Integration: 在完成 Unit 2 的 symlink 迁移后，后续多次 sync 只更新受管共享资产和生成 settings，不再把 runtime 内容复制回 repo。

**Verification:**
- 共享资产同步边界可以通过脚本常量和测试直接看懂，不需要再靠阅读 `.gitignore` 猜测。
- sync 重复运行不会破坏非受管运行态目录，也不会把 secrets 写回 shared template。

- [ ] **Unit 4: 更新使用文档与迁移说明**

**Goal:**  
让用户明确知道“共享默认配置改哪里、本机 secrets 改哪里、全局生成文件不要手改”，并记录从旧 symlink 模式迁移到新模式的行为变化。

**Requirements:**  
R2, R7, R9, R11

**Dependencies:**  
Unit 3

**Files:**
- Modify: `ai/coding/claude/docs/config.md`
- Modify: `ai/coding/claude/docs/CLAUDE_CODE_CHEATSHEET.md`
- Modify: `ai/coding/claude/Sync-ClaudeConfig.ps1`

**Approach:**
- 在 `ai/coding/claude/docs/config.md` 中补充仓库专用的备份/同步说明，明确区分：
  - `ai/coding/claude/config/settings.json` 是 shared template
  - `ai/coding/claude/config/settings.local.json` 是本机覆盖
  - `~/.claude/settings.json` 是生成产物
- 在 `ai/coding/claude/docs/CLAUDE_CODE_CHEATSHEET.md` 中修正文档里“`.claude/settings.json` 直接提交到版本控制”的泛化表达，至少在仓库自己的工作流段落中说明这里采用的是模板 + local + generated 模式。
- 给 `ai/coding/claude/Sync-ClaudeConfig.ps1` 顶部帮助注释补齐新的职责、迁移行为和 first-run 风险提示。

**Patterns to follow:**
- `ai/coding/claude/docs/config.md`
- `config/gemini-cli/Apply-GeminiCliConfig.ps1` 的帮助注释风格

**Test scenarios:**
- Test expectation: none -- 这是文档与脚本帮助更新，不引入独立行为分支；其正确性通过内容审阅和前序脚本测试保障。

**Verification:**
- 用户只看文档就能分清 shared template、local override、generated file 三个层级。
- 旧 workflow 的“手改 `~/.claude/settings.json`”习惯被明确废止，迁移后入口没有歧义。

## System-Wide Impact

- **Interaction graph:** `ai/coding/claude/config/settings.json` 与可选的 `ai/coding/claude/config/settings.local.json` 会共同驱动 `ai/coding/claude/Sync-ClaudeConfig.ps1`，后者再把结果写入 `~/.claude/settings.json` 并同步 `ai/coding/claude/.claude/` 下的受管共享资产。
- **Error propagation:** shared template 校验失败、local JSON 解析失败、target 目录迁移失败都必须在写入前中止，并保留最后一个可工作的 target 配置或 backup。
- **State lifecycle risks:** 最大风险点是旧 symlink 迁移和受管路径 prune；两者都要通过 backup 和 temp-dir 测试覆盖，避免误删运行态数据。
- **API surface parity:** `ai/coding/claude/Sync-ClaudeConfig.ps1` 的调用入口保持不变；变化集中在内部职责和 repo 文件布局。
- **Integration coverage:** 需要真正模拟 repo source dir、home dir、旧 symlink 目标和运行态文件共存场景，单纯的 pure-function merge 测试不足以证明迁移安全。
- **Unchanged invariants:** Claude 仍然从 `~/.claude` 读取最终生效配置；`ai/coding/claude/.claude/commands/`、`output-styles/`、`skills/` 等共享资产仍然继续由仓库版本控制。

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| 旧 symlink 迁移时丢失运行态历史或缓存 | 首次迁移前生成 backup，并用脚本测试覆盖 symlink-to-real-directory 迁移路径 |
| merge 语义与用户直觉不一致，导致 local 覆盖结果出错 | 明确对齐 Claude 官方继承直觉，并用具体 fixture 测试对象、数组、标量三类覆盖 |
| scoped prune 误删非受管目录 | 只允许在受管路径内 prune，且测试覆盖“受管删除不波及非受管目录” |
| 共享模板再次混入 secrets | 在 sync 脚本内增加阻断式 guardrail，文档里明确 shared / local 的职责 |
| 本机没有 `settings.local.json` 时用户误以为 sync 失败 | 文档与脚本输出明确说明 local 为 optional，provider 差异与 secrets 需要时再创建 |

## Documentation / Operational Notes

- 本计划落地后，`ai/coding/claude/config/settings.json` 会成为 repo 内唯一应提交审阅的 Claude settings 源。
- `ai/coding/claude/config/settings.local.json` 应继续依赖现有 `*.local.json` 忽略规则，不额外提交示例中携带真实 secrets 的本机文件。
- 首次迁移需要在脚本输出中明确提示：`~/.claude/settings.json` 以后不要手改，如需变更应修改 shared template 或 local override 后重新运行 sync。

## Sources & References

- **Origin document:** `docs/brainstorms/2026-04-03-claude-settings-split-brainstorm.md`
- Related code: `ai/coding/claude/Sync-ClaudeConfig.ps1`
- Related code: `ai/coding/claude/.gitignore`
- Related code: `ai/coding/claude/config/user.settings.json`
- Related code: `config/gemini-cli/Apply-GeminiCliConfig.ps1`
- Related test pattern: `tests/Sync-PathFromBash.Tests.ps1`
- External docs: <https://docs.anthropic.com/en/docs/claude-code/settings>
