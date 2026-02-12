## 1. 状态概览增强（Step 3）

- [ ] 1.1 在 SKILL.md 的 Step 3 中新增 Health 列：对每个 feature worktree 执行 `git cherry <base> <branch>`，统计重复 commit 比例并显示（✔ / ℹ / ⚠）
- [ ] 1.2 更新状态表格模板，添加 Health 列示例
- [ ] 1.3 更新 `openspec/specs/worktree-sync/spec.md` 中的「状态概览显示」requirement

## 2. Cherry 诊断步骤（新增 Step 4.4.1）

- [ ] 2.1 在 SKILL.md 的 Step 4.4 之后新增 Step 4.4.1：执行 `git cherry <base> <branch>`，统计 unique/dup 数量
- [ ] 2.2 实现策略决策矩阵：unique=0 → reset；dup/total>50% → reset+cherry-pick；否则 → rebase
- [ ] 2.3 保存诊断前 HEAD SHA（用于批量模式回滚）
- [ ] 2.4 显示诊断信息（策略类型、重复数、独有 commit 列表）

## 3. Reset + Cherry-pick 策略（新增 Step 4.5a）

- [ ] 3.1 在 SKILL.md 中新增 Step 4.5a：reset 策略执行流程（`git reset --hard <base>`）
- [ ] 3.2 新增 Step 4.5b：reset + cherry-pick 策略执行流程（reset 后逐个 cherry-pick unique commits）
- [ ] 3.3 新增 cherry-pick 冲突处理：单分支模式提供三选项（Claude 协助 / 手动 / 中止）
- [ ] 3.4 修改 Step 4.5/4.6 为仅在标准 rebase 策略时执行

## 4. 批量同步适配（Step 6）

- [ ] 4.1 修改 Step 6.3：每个分支独立执行 cherry 诊断 + 策略选择
- [ ] 4.2 实现批量模式下 cherry-pick 冲突的回滚逻辑：abort + reset 到原始 HEAD
- [ ] 4.3 更新汇总报告模板：增加使用的策略列

## 5. 成功报告更新（Step 5）

- [ ] 5.1 修改 Step 5 报告格式：增加「同步策略」字段（rebase / reset / reset+cherry-pick）

## 6. Spec 同步

- [ ] 6.1 新增 `openspec/specs/cherry-diagnosis/spec.md`（从 change delta spec 合并）
- [ ] 6.2 更新 `openspec/specs/worktree-sync/spec.md`（合并 modified requirements）
