---
date: 2026-04-03
topic: claude-settings-split
---

# Claude `settings.json` 拆分与同步分层方案

## Problem Frame

当前 Claude 配置同步依赖 `ai/coding/claude/Sync-ClaudeConfig.ps1` 将 `ai/coding/claude/.claude` 整体映射到 `~/.claude`。这套模式在早期足够省事，但现在已经暴露出两个结构性问题：

1. `ai/coding/claude/.claude/settings.json` 既承载共享默认配置，也可能直接包含 `ANTHROPIC_API_KEY`、`ANTHROPIC_BASE_URL` 等敏感环境变量。
2. `ai/coding/claude/.claude` 目录同时承担共享配置仓和本机运行态目录的职责，导致 backup、history、debug、sessions、transcripts 等状态数据与真正应入库的配置混在一起。

这次 brainstorm 的目标不是单纯“再补几个 `.gitignore` 条目”，而是重新定义 Claude 配置的边界：哪些配置应该共享、哪些配置必须本机私有、哪些内容根本不应该进入仓库同步流程。

## What We're Building

我们要把 Claude 配置调整成一套分层模型：

- 仓库里只保留安全、可共享、可审阅的默认配置与共享资产。
- 本机单独保留 secrets 与个人环境差异，不进入 Git。
- 同步脚本负责组装最终的 `~/.claude/settings.json`，而不是把整个目录直接暴露给仓库。

| 层级 | 位置 | 内容 | 是否入库 |
|---|---|---|---|
| 共享模板层 | 仓库内模板文件 | 非敏感默认配置、共享资产、非敏感 `env` 默认值 | 是 |
| 本机覆盖层 | `settings.local.json` | secrets、provider 差异、个人偏好覆盖 | 否 |
| 生成结果层 | `~/.claude/settings.json` | 由前两层合并后的最终生效配置 | 否 |

## Why This Approach

你已经明确觉得“拆分 `settings.json`”比继续黑名单更合理，这个判断和仓库现状是吻合的。当前问题的根因不是黑名单覆盖不全，而是文件职责本身不清晰。

相比“继续把 `.claude` 当一个整体目录管理”，分层式 `settings.json` 有三个明显优势：

- secrets 的承载位置更明确，不容易误提交。
- router / 直连等 provider 差异可以变成可切换配置，而不是反复手改同一个文件。
- 后续可以逐步把同步逻辑从“整目录软链”迁移到“显式白名单 + 生成产物”，风险更可控。

## Approaches

| 方案 | 描述 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| A. 继续黑名单 | 保留现有整目录同步，只扩充 `ai/coding/claude/.gitignore` | 改动最小 | 根因未解，已跟踪 `settings.json` 仍可能泄漏 secrets | 不推荐 |
| B. 基础模板 + 本机覆盖 + 生成最终文件 | 仓库保留 `settings.base.json`，本机保留 `settings.local.json`，同步脚本合并生成真实 `settings.json` | 兼顾安全性、灵活性与可迁移性 | 需要定义合并规则与文件命名 | 推荐 |
| C. 纯 profile 文件驱动 | 仓库保留多个 provider profile，由用户切换 profile 并在本机提供 secrets | provider 切换清晰 | 对“哪些配置从哪来”更绕，用户操作链更长 | 暂不采用，后续可扩展 |

## Requirements

**配置分层**
- R1. Claude 共享默认配置必须与本机 secrets 分离，默认仓库文件中不得出现真实 `ANTHROPIC_API_KEY` 或等价敏感值。
- R2. 仓库必须保留一份可提交、可审阅、可复制的 Claude 默认配置模板，作为新机器初始化入口。
- R3. 本机私有配置必须支持不入库覆盖，并与仓库默认模板合并生成最终生效配置。

**同步行为**
- R4. `Sync-ClaudeConfig.ps1` 的职责应从“整目录映射”收敛为“同步共享资产 + 生成最终 settings”。
- R5. 同步过程中必须显式排除运行态数据目录，不再让 history、debug、sessions、transcripts、backups 等内容参与仓库同步。
- R6. 同步逻辑必须兼容至少两类 provider 场景：router 模式与直接配置 API key 的模式。
- R11. `~/.claude/settings.json` 必须被视为生成产物；sync 时可直接覆盖，日常修改入口不应再指向全局生成文件。

**安全与可维护性**
- R7. 新结构必须让用户容易判断“该改哪个文件”，避免继续把个人配置误写到可提交文件。
- R8. 同步前应具备基础的敏感字段保护机制，至少能阻止明显的 API key 被写入仓库模板。
- R9. 新结构应尽量复用仓库现有的 `*.local.json` / `.env.local` 约定，减少新的心智负担。
- R10. `settings.local.json` 必须支持按键级别的局部覆盖与深度合并，避免用户为了覆盖单个 `env` 或插件开关而复制整段对象。

## Success Criteria

- 在默认推荐流程下，用户不需要把任何真实密钥写入可提交的 `settings` 模板文件。
- 新机器初始化 Claude 配置时，仍然可以通过仓库内模板快速完成落地。
- router 与直连两种 provider 方式都能在不修改共享模板 secrets 的前提下正常切换。
- 后续即使继续扩展 `.claude` 目录内容，也不会再把运行态缓存误当成可同步配置。
- 用户只需要在 `settings.local.json` 中声明少量差异字段，而不需要复制整段 `env`、`enabledPlugins` 或其他对象。
- 用户不需要也不应直接编辑 `~/.claude/settings.json`；sync 重新生成后不会丢失任何正式配置来源中的变更。

## Scope Boundaries

- 这次不讨论是否接入系统级密码管理器、1Password、gopass 等更重的密钥管理系统。
- 这次不要求一次性重构所有 Claude 相关脚本，只聚焦配置文件边界与同步方式。
- 这次不在 brainstorm 阶段锁定具体 PowerShell 实现细节，如函数拆分、JSON merge 代码形态、异常处理细节。

## Key Decisions

- 采用方案 B 作为主线：基础模板 + 本机覆盖 + 生成最终文件。
  理由：这是最平衡的方案，既能处理 secrets，又不会把 provider 切换做得过重。

- 本机覆盖层采用 `settings.local.json` 作为主入口。
  理由：后续除了 `env`，还可能覆盖 `model`、`enabledPlugins`、`statusLine` 等结构化字段，JSON 覆盖文件比单纯 env 文件更自然。

- 首版不引入 provider profile 层，router / 直连都直接通过 `settings.local.json` 覆盖。
  理由：当前首要目标是把共享配置和本机配置拆干净，先减少配置层数，再为后续 profile 扩展预留空间。

- `env` 采用“共享默认值 + 本机敏感覆盖”模式。
  理由：像超时、telemetry、attribution 这类稳定且非敏感的默认值适合放在共享模板中；`ANTHROPIC_API_KEY`、`ANTHROPIC_BASE_URL` 这类 secrets 或 provider 差异只应出现在 `settings.local.json`。

- `settings.local.json` 采用按键级别的局部覆盖与深度合并，而不是整段替换。
  理由：这样用户只需要声明差异项，既减少重复，也降低因复制旧模板导致配置漂移的风险。

- `~/.claude/settings.json` 被定义为纯生成产物，sync 可直接覆盖。
  理由：这样配置真源只有“共享模板 + `settings.local.json`”，避免再次出现“用户手改全局文件、脚本又不知道该相信谁”的边界混乱。

- 黑名单 `.gitignore` 只能作为兜底，而不再作为核心安全机制。
  理由：黑名单难以覆盖所有新文件，且无法修复已跟踪文件职责错误的问题。

## Dependencies / Assumptions

- 假设 Claude 最终仍以 `~/.claude/settings.json` 作为主要生效入口。
- 假设当前仓库允许新增一到两个本地覆盖文件命名约定，并通过 `.gitignore` 统一排除。
- 假设现有 `ai/coding/claude/config/user.settings.json` 可作为模板分层时的参考，而不是继续直接复用当前 `.claude/settings.json`。

## Outstanding Questions

### Deferred to Planning

- [Affects R4][Technical] 同步脚本是直接做深度 JSON merge，还是先生成中间对象再整体写回 `~/.claude/settings.json`？
- [Affects R5][Technical] 除 `settings` 之外，哪些目录应进入同步白名单，哪些目录应完全改为仅本机存在？
- [Affects R8][Technical] secret guardrail 应放在同步脚本、pre-commit，还是两者都放？

## Next Steps

-> `/ce:plan` 把文件结构、`settings.local.json` 合并规则、脚本职责、迁移步骤与验证策略具体化
