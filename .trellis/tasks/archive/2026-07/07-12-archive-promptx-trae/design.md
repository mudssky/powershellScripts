# PromptX 与 Trae 归档设计

## 1. 迁移映射

| 源路径 | 归档路径 | 索引 ID | 替代或恢复说明 |
|---|---|---|---|
| `.promptx` | `archive/.promptx` | `batch-3-promptx` | 仅供历史参考；活动 PromptX MCP 配置位于 `ai/mcp` |
| `.trae` | `archive/.trae` | `batch-3-trae` | 使用 `.agents/skills` 与现有 Claude/Codex 配置 |
| `openspec` | `archive/openspec` | `batch-3-openspec` | 使用 `.trellis` 任务、规范与工作流 |

三项分开调用归档 CLI，因为原因和替代入口语义不同。移动期间不修改目录内文件正文，以保留 Git rename 识别。

## 2. 引用分类

### 必须更新

- `README.md`：根目录树描述当前仓库结构。
- `.betterleaksignore`：扫描例外必须跟随真实文件路径。
- `docs/plans/2026-04-05-001-refactor-fnos-mount-manager-plan.md`：当前计划仍直接引用两个 Trae 历史文档，应指向归档镜像。
- `turbo.json`：删除已无源目录的 OpenSpec 专用排除，根 `archive/**` 排除继续生效。
- `profile/installer/apps-config.json`：删除已退出工作流的 OpenSpec CLI 安装项。
- `docs/plans/**`：将明确的 `openspec/specs/**` 文件路径改到归档镜像，保留其历史上下文。

### 保持不变

- `.trellis/scripts/**`、`.claude/hooks/**`、`.codex/hooks/**`：通用 Trae 平台支持。
- `.agents/skills/trellis-meta/**`、`.claude/skills/trellis-meta/**`：跨平台架构文档。
- `scripts/node/src/rule-loader/**` 与测试：独立的 Trae 规则格式工具，测试自行创建临时 `.trae/rules`。
- `scripts/ahk/.promptx/**`：独立 PromptX 子项目。
- `ai/coding/claude/docs/插件指南.md`：外部工具资料，不代表本仓库启用 OpenSpec 工作流。
- `.trellis/tasks/archive/**`、`scripts/node/.claude/archived_plans/**`：历史事实记录。
- `.trellis/.template-hashes.json`：Trellis 运行态文件，由更新工具管理且 safe-commit 明确排除。

## 3. 执行顺序

1. 确认工作区除当前任务外干净，运行索引 `check`。
2. 使用三个已审阅的 `plan` 参数分别执行 `archive --execute`。
3. 更新 README、betterleaks 和当前计划文档路径。
4. 再次搜索根 `.promptx`、`.trae` 引用并按分类复核。
5. 运行索引检查、QA 和 Git rename/history 验证。

## 4. 回滚

- 任一 CLI 调用失败时先检查其自动回滚结果和 `git status`。
- 完整回滚使用反向 `git mv archive/.promptx .promptx`、`git mv archive/.trae .trae`、`git mv archive/openspec openspec`，删除对应 JSON 条目并恢复活动引用。
- `.vercel` 不参与写操作，无需回滚。

## 5. 风险

- betterleaks fingerprint 的路径变化若未同步，会导致预提交 secret 扫描重新报出历史内容。
- Trellis 更新工具未来可能依据模板策略重新生成 `.trae`；本任务不改运行态 hash 清单，若实际发生再通过 Trellis 平台配置能力处理，不提前修改上游兼容代码。
- 根 `.trae` 移除后 rule-loader 无参数运行会找不到默认目录；该 CLI 本身是 Trae 格式工具，用户仍可通过 `--source` 指定目录，本任务不改变其产品语义。
- OpenSpec spec 路径大量出现在历史计划中；只迁移明确路径，不把普通“OpenSpec”名词批量改写成 Trellis，避免篡改历史语义。
