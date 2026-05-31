# implement.md

## 实施顺序

### Phase 1：操作安全性（state.py 核心）

**1.1 实现 `merge_folder` 操作**
- 文件：`state.py` SUPPORTED_OPS + apply_operation
- 语义：`fromPath` 的所有直接书签和子目录移到 `toPath`，然后删除 `fromPath`
- `toPath` 必须已存在（`ensure_folder` 可选）
- 验证：`test_merge_folder` 单元测试

**1.2 操作字段校验**
- 文件：`state.py` 新增 `validate_operation(op)` 函数
- 每种 op 类型定义必填字段：
  - `move_folder`: fromPath, toPath
  - `create_folder`: path
  - `delete_empty_folder`: path
  - `rename_folder`: fromPath, toPath
  - `move_bookmark`: bookmarkId, toPath
  - `rename_bookmark`: bookmarkId, title
  - `update_url`: bookmarkId, url
  - `mark_bookmark`: bookmarkId, mark
  - `archive_bookmark`: bookmarkId
  - `merge_folder`: fromPath, toPath
- 缺字段时 raise ValueError 并列出缺失字段名
- 调用点：`run_apply_ops_command` 在 replay 前先校验所有 incoming ops
- 验证：`test_validate_operation_missing_fields`

**1.3 normalize_operation 默认 approved 处理**
- 文件：`state.py` normalize_operation
- 保持默认 `approved: True`（因为 apply-ops 是显式提交命令）
- 但在 `cli.py` 的 dry-run 路径中明确注释：dry-run 不写入，所以不需要 approved 标记

### Phase 2：CLI 改进

**2.1 统一 `--input` 为 CLI 主名**
- 文件：`cli.py` apply-ops parser
- 改为 `add_argument("--input", "--ops-file", dest="ops_file", ...)`
- `--input` 显示在 help，`--ops-file` 作为隐藏别名
- 更新 SKILL.md 如果有引用 `--ops-file` 的地方

**2.2 实现 `undo` 命令**
- 文件：`cli.py` 新增 `undo` subcommand
- 参数：`--workspace`（必填）、`--last N`（必填，回退最近 N 个操作）、`--dry-run`（预览）
- 行为：读取 operations.jsonl，截断最后 N 行，写回文件
- dry-run：输出被回退的操作摘要（op, reason, 目标路径），不写入
- 验证：手动测试 + 检查 operations.jsonl 行数

**2.3 dry-run 输出操作摘要**
- 文件：`cli.py` run_apply_ops_command
- dry-run 时遍历 incoming ops，输出每个操作的 fromPath/toPath/bookmarkId
- 格式：JSON 数组，每个元素含 `{op, summary}` 例如 `{"op": "move_folder", "summary": "A/B/C → A/C"}`
- 与现有 `{"ok": true, "dryRun": true}` 合并输出

**2.4 修复端口复用时 PID 显示 None**
- 文件：`cli.py` start_review_server_background
- 端口复用时，读取 `review-server.pid` 文件获取实际 PID
- PID 文件不存在时显示 `运行中` 而非 `None`

### Phase 3：WebUI 改进

**2.5 重复项表格展开详情**
- 文件：`review_server.py` get_analysis endpoint，`review.js` renderDuplicates
- 在 analysis payload 的 duplicates 数据中包含每组的具体书签（id, title, folderPath）
- 前端每组可展开，显示书签列表（标题、目录、链接）

### Phase 4：文档更新

**4.1 SKILL.md 补充**
- 添加 SUPPORTED_OPS 列表，每种 op 及其必填字段
- 补充 workspace 默认路径说明
- 更新 `--input` 示例（确认与 CLI 一致）

**4.2 workflow.md 修正**
- 移除或更新 `merge_folder` 描述（现已实现）
- 确认 4 个阶段描述与实际一致

## 验证命令

```bash
cd ai/skills/dev/browser-bookmark-organizer

# 运行现有测试
uv run pytest tests/ -v

# 手动验证 merge_folder
uv run python -c "
from browser_bookmark_organizer.state import SUPPORTED_OPS
assert 'merge_folder' in SUPPORTED_OPS
print('merge_folder OK')
"

# 手动验证 undo
uv run python -m browser_bookmark_organizer.cli undo --help

# 手动验证 dry-run 摘要
# 需要先有 workspace，用已有 bookmark-runs/run-001 测试
```

## 风险文件

- `state.py`：apply_operation 是核心 replay 逻辑，改动需确保不破坏现有操作
- `cli.py`：新增 undo 命令，注意截断 operations.jsonl 时不要误删
