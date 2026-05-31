# 书签整理 skill 流程优化

## Goal

基于一次完整的 1499 书签整理实战，修复 skill 的实际痛点，让下一轮整理更顺畅。核心方向：减少 agent 与 CLI 的来回切换、提升操作安全性、补齐文档与代码的不一致。

## 实战发现的问题（按优先级）

### P0：会导致运行失败

1. **`merge_folder` 在 workflow.md 和 SKILL.md 中文档化，但 `SUPPORTED_OPS` 未实现**（state.py:13-23）
   - agent 按 workflow 生成 `merge_folder` 操作 → apply 时报错「不支持的 operation」
   - 本次会话我们绕过了它（用 move + delete 组合替代），但其他 agent 可能不会

2. **操作字段缺失时抛 KeyError 而非友好错误**（state.py:109-144）
   - `move_bookmark` 缺 `bookmarkId` 或 `toPath` → 原始 KeyError，不告诉 agent 哪个字段缺
   - 本次会话多次踩坑（用了错误的字段名 `action` 而非 `op`）

3. **SKILL.md 文档的 `--input` 与 CLI 主名 `--ops-file` 不一致**（SKILL.md:44 vs cli.py:126-132）
   - agent 读文档写 `--input`，CLI help 显示 `--ops-file`

### P1：操作安全性

4. **`normalize_operation` 默认 `approved: True`**（state.py:558-563）
   - 违反 workflow.md「只有用户批准的 operation 才写入 operations.jsonl」原则
   - 任何省略 `approved` 字段的操作都被静默接受

5. **无 undo/rollback 命令**
   - 本次会话误操作 127 个 archive 后，只能手动编辑 `operations.jsonl` 截断
   - 应有 `undo --last N` 或 `rollback --to-operation <id>`

6. **dry-run 不报告变更预览**
   - `--dry-run` 只返回 `{"ok": true, "operationCount": N}`，不显示会影响哪些目录/书签
   - agent 无法根据 dry-run 输出判断操作是否合理

### P2：CLI 体验

7. **默认 workspace 路径行为文档缺失**
   - 省略 `--workspace` 时数据写入 `~/.local/state/...`，但 SKILL.md 未提及
   - agent 不知道数据去了哪里

8. **后台服务 PID 显示 `None`**（cli.py:698）
   - 端口复用时返回 `pid=None`，stdout 输出 `Review PID: None` 令人困惑

9. **`--no-follow-redirects` 是双重否定**
   - 默认跟随重定向，flag 否定默认 → 应改为 `--follow-redirects` (默认 True)

### P3：WebUI 功能缺口

10. **无法从 WebUI 提交操作**
    - 所有操作必须 agent 生成文件 → CLI apply-ops → 刷新 WebUI
    - 理想：WebUI 可粘贴 JSON 直接提交

11. **重复项表格无展开详情**
    - 只显示 URL 和数量，不显示各书签标题和 ID
    - 无法在 WebUI 中决定保留哪个

12. **无阶段进度展示**
    - workflow.md 定义了 4 个阶段，但 WebUI 没有阶段分组或进度指示

### P4：文档与一致性

13. **SKILL.md 未列出实际支持的 operation 类型**
    - agent 只能从 workflow.md 推断，但 workflow.md 包含未实现的类型
    - 需在 SKILL.md 或独立文档明确列出 SUPPORTED_OPS 及每种所需字段

14. **`decisions.json` 无法记录拒绝原因**
    - workflow.md 说「被拒绝的方案可记录在 decisions.json」
    - 实际 decisions API 只保存勾选和备注，无结构化拒绝记录

15. **review --log-file 在 SKILL.md 暗示特殊组合，实际就是普通 flag**

## Requirements

1. 实现 `merge_folder` 操作（或从文档中移除）
2. 为每种 op 类型添加必填字段校验，缺失时返回清晰的字段名提示
3. 统一 `--input` 为 CLI 主名（别名保留 `--ops-file`）
4. `normalize_operation` 默认 `approved: false`，CLI `apply-ops` 显式设为 `true`
5. 新增 `undo` 命令：`undo --last N` 回退最近 N 个操作
6. `dry-run` 输出包含操作摘要（每个 op 的目标路径/书签）
7. SKILL.md 补充：workspace 默认路径说明、SUPPORTED_OPS 完整列表
8. 修复端口复用时 PID 显示为 None 的问题
9. 重复项表格增加展开详情（显示每组的书签标题和 ID）

## Acceptance Criteria

- [ ] `merge_folder` 操作可正常 apply，或从 workflow.md/SKILL.md 移除
- [ ] 缺少必填字段时，apply-ops 返回「操作 #N 缺少必填字段: bookmarkId, toPath」
- [ ] `--input` 作为 CLI 主名显示在 help 中
- [ ] 新写入 operations.jsonl 的操作默认 approved=true（显式），dry-run 不写入
- [ ] `undo --last 3` 可回退最近 3 个操作并输出回退摘要
- [ ] `dry-run` 输出每个操作的 fromPath/toPath/bookmarkId 摘要
- [ ] SKILL.md 包含 SUPPORTED_OPS 列表和每种所需字段
- [ ] 端口复用时 stdout 输出实际 PID 而非 None
- [ ] 重复项表格可展开查看每组的书签标题

## Out of Scope

- WebUI 在线提交操作（P3-10，复杂度高，后续独立任务）
- 阶段进度 UI（P3-12，需要后端 phase 跟踪支持）
- `--follow-redirects` flag 重命名（P2-9，破坏性变更）
- `delete_bookmark` 操作（需要安全讨论）
- corrupted JSONL 容错恢复

## Open Questions (Resolved)

- ~~`merge_folder` 的语义~~ → **实现**：把源目录的直接书签和子目录移到目标目录，然后删除源目录
- ~~`undo` 是否需要确认提示~~ → **不加确认**，agent 场景下确认会卡住流程；支持 `--dry-run` 预览
