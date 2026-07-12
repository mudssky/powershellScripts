# 执行计划

## 1. 执行前基线

- [x] 记录 `git status --short`，确认并保留无关未跟踪任务目录。
- [x] 记录 `git ls-files ai` 数量和 `git clean -ndX ai` 列出的本机内容。
- [x] 运行归档工具 `check`，确认当前 `archive/index.json` 有效。
- [x] 使用最终原因和替代说明运行 `plan ai`，审查真实活动引用和目标 `archive/ai`。

## 2. 归档提交

- [x] 使用与计划相同的参数运行 `archive ai --execute`。
- [x] 检查 `git status`、`git diff --cached --summary` 和 rename 识别。
- [x] 运行归档工具 `check`。
- [x] 确认迁入 `archive/ai/` 的正文未被改写。
- [x] 提交 `chore(archive): 归档 AI 工具目录`。

## 3. 活动入口清理

- [x] 从 `pnpm-workspace.yaml` 移除 `ai/skills/dev/*` 并机械更新 `pnpm-lock.yaml`。
- [x] 从 `Manage-BinScripts.ps1` 移除 `ai/` 示例和默认扫描模式。
- [x] 从 `powershellScripts.code-workspace` 移除 AI 专属配置。
- [x] 更新根 `README.md` 与 `CLAUDE.md`，不再把 `ai/` 描述为活动目录；需要时注明历史内容位于 `archive/ai/`，但不提供运行指引。
- [x] 删除仅验证已归档 AI 工具的 3 个 Pester 测试文件。
- [x] 分别归档 `.trellis/spec/infra/agent-skill-dev.md`、`coding-plan-window-warmer.md`、`hermes-agent-layout.md`、`litellm-gateway.md`，并从 infra 索引移除对应条目。
- [x] 检索活动树中的 `ai/` 路径引用并逐项判断，清除有效运行引用。

## 4. 验证

- [x] 运行归档工具 `check`。
- [x] 运行 `pnpm qa`。
- [x] 运行 `pnpm test:pwsh:all`。
- [x] 确认 `git ls-files ai` 为空，`git ls-files archive/ai` 数量与基线一致。
- [x] 确认本机忽略内容未被纳入 Git，且无关未跟踪任务目录未被修改。
- [x] 检查最终 diff 不包含归档正文改写或其他无关改动。

## 5. 收尾提交

- [x] 提交 `chore(ai): 移除已归档工具入口`。
- [x] 记录已归档内容、被移除入口、本机保留内容和恢复步骤。

## 回滚点

- 归档工具执行失败时，先查看工具报告的已移动路径与自动回滚结果，再用 `git status` 核对。
- 归档提交之后出现问题时，优先 revert 两个独立提交；不要手工复制归档正文。
