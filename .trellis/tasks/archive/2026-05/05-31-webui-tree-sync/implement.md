# WebUI 可折叠目录树与 ops 状态同步 — 实现计划

## 前置条件

- dev skill 源码在 `ai/skills/dev/browser-bookmark-organizer/`
- 修改完成后 rsync 到 `.claude/skills/browser-bookmark-organizer/`

## 步骤

### Step 1: `state.py` — 增强 `build_tree_payload`

- [ ] 新增辅助函数 `_build_nested_tree(state)` 递归构建嵌套结构
- [ ] `build_tree_payload` 返回值增加 `tree` 字段，包含 `children` 嵌套和直属书签
- [ ] 验证：运行现有测试 + 手动调用确认 JSON 结构

### Step 2: `review.js` — 可折叠目录树

- [ ] 新增 `expandedFolders` Map 存储折叠状态
- [ ] 重写 `renderTree()` 使用递归 DOM 构建
- [ ] 文件夹行：箭头 + 名称 + 书签数 badge
- [ ] 展开后显示直属书签列表（>20 时截断 + "显示更多"）
- [ ] 点击文件夹行 toggle 展开状态

### Step 3: `review.js` — ops 状态同步

- [ ] 新增 `pollAnalysis()` 函数，对比 `operationCount`
- [ ] `loadData()` 完成后启动轮询
- [ ] `visibilitychange` 事件控制暂停/恢复
- [ ] 手动刷新按钮绑定

### Step 4: `review.html` + `review.css` — UI 改动

- [ ] topbar 添加刷新按钮
- [ ] 新增树节点、折叠箭头、书签行样式

### Step 5: 集成验证

- [ ] rsync 到 `.claude/skills/`
- [ ] uv sync 重建环境
- [ ] 用现有 workspace 运行 review 验证
- [ ] CLI apply-ops 后观察 WebUI 自动刷新
