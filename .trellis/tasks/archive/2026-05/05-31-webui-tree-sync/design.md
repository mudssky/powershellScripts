# WebUI 可折叠目录树与 ops 状态同步 — 技术设计

## 1. 数据层改动

### 1.1 `state.py` — `build_tree_payload` 增强返回结构

当前 `build_tree_payload` 返回扁平 folder 列表。改为同时提供嵌套结构，让前端无需自行构建树。

新增字段 `tree`：嵌套对象，结构如下：

```json
{
  "folderCount": 626,
  "bookmarkCount": 1494,
  "folders": [/* 扁平列表，保持向后兼容 */],
  "tree": {
    "children": [
      {
        "name": "Bookmarks bar",
        "path": ["Bookmarks bar"],
        "bookmarkCount": 5,
        "bookmarks": [
          {"id": "b_000001", "title": "...", "url": "..."}
        ],
        "children": [
          {
            "name": "code",
            "path": ["Bookmarks bar", "code"],
            "bookmarkCount": 3,
            "bookmarks": [],
            "children": []
          }
        ]
      }
    ]
  }
}
```

`bookmarks` 只包含直属书签（非递归），`bookmarkCount` 为直属数量。嵌套通过共享的 `child_folder_names` 和 `sorted_bookmarks_in_folder` 函数实现。

### 1.2 `review_server.py` — 无需 API 改动

`/api/analysis` 已在每次请求时 replay operations 并调用 `build_tree_payload`，天然实时。无需新端点。

## 2. 前端改动

### 2.1 可折叠目录树 (`review.js`)

**数据结构**：使用后端返回的 `tree` 字段递归渲染。

**渲染函数** `renderTree()` 重写：

- 从 `state.analysis.currentTree.tree.children` 递归生成 DOM。
- 每个文件夹节点包含：展开箭头（▶/▼）、文件夹名、直属书签数 badge。
- 折叠状态存储在 JS Map `expandedFolders: Map<string, boolean>` 中，key 为 path 字符串。
- 点击文件夹行时 toggle `expandedFolders` 并仅重新渲染该子树。

**直属书签展示**：

- 展开文件夹后，先渲染直属书签（标题 + 可点击 URL），再渲染子文件夹。
- 书签数量多时（>20），默认只显示前 20 个，点击"显示更多"展开。

### 2.2 ops 状态同步 (`review.js`)

**轮询机制**：

```js
let pollTimer = null;
const POLL_INTERVAL = 5000;
let lastOperationCount = 0;

function startPolling() {
  pollTimer = setInterval(pollAnalysis, POLL_INTERVAL);
}

async function pollAnalysis() {
  const res = await fetch("/api/analysis");
  const data = await res.json();
  const newCount = data.workspaceStatus?.operationCount ?? 0;
  if (newCount !== lastOperationCount) {
    lastOperationCount = newCount;
    state.analysis = data;
    render();
  }
}
```

**可见性控制**：

- `document.addEventListener("visibilitychange", ...)`
- hidden 时 `clearInterval`，visible 时立即 `pollAnalysis()` 然后 `startPolling()`。

**手动刷新按钮**：

- 在 topbar-actions 区域添加刷新按钮，点击时立即调用 `pollAnalysis()`。

### 2.3 CSS 改动 (`review.css`)

新增样式：

```css
.tree-node { margin-left: 16px; }
.tree-toggle { cursor: pointer; user-select: none; }
.tree-toggle .arrow { display: inline-block; width: 16px; transition: transform 150ms; }
.tree-toggle.open .arrow { transform: rotate(90deg); }
.tree-children { overflow: hidden; }
.tree-children.collapsed { display: none; }
.tree-bookmark { padding: 4px 0 4px 20px; font-size: 13px; }
.tree-bookmark a { color: var(--primary); text-decoration: none; }
.tree-bookmark a:hover { text-decoration: underline; }
.tree-show-more { color: var(--muted); font-size: 12px; cursor: pointer; padding: 4px 0 4px 20px; }
```

## 3. 不做的事

- 不添加 WebSocket/SSE — 轮询对本地单用户场景足够。
- 不在前端执行 operation — 操作仍通过 CLI `apply-ops` 提交。
- 不引入虚拟滚动 — 600 文件夹 + 1500 书签在 DOM 中完全可承受。

## 4. 文件改动清单

| 文件 | 改动 |
|---|---|
| `state.py` | `build_tree_payload` 增加 `tree` 嵌套结构和直属书签 |
| `review.js` | 重写 `renderTree`、新增 `pollAnalysis`/轮询逻辑、刷新按钮 |
| `review.css` | 新增树节点、折叠箭头、书签行样式 |
| `review.html` | topbar 区域添加刷新按钮 |
