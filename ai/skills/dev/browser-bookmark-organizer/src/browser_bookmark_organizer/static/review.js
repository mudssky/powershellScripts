const state = {
  activeView: "overview",
  analysis: null,
  decisions: { selected: {}, note: "" },
  linkProgress: null,
  linkSearch: "",
  linkFilter: "",
};

// 折叠状态持久化：key 为 path 字符串（如 "Bookmarks bar,code"）
const expandedFolders = new Map();
const POLL_INTERVAL = 5000;
const LINK_POLL_INTERVAL = 2000;
let pollTimer = null;
let linkPollTimer = null;
let lastOperationCount = 0;

const workspacePath = document.querySelector("#workspacePath");
const serverUrl = document.querySelector("#serverUrl");
const serverTtl = document.querySelector("#serverTtl");
const nextActionText = document.querySelector("#nextActionText");
const summaryGrid = document.querySelector("#summaryGrid");
const actionGrid = document.querySelector("#actionGrid");
const treeList = document.querySelector("#treeList");
const linkRows = document.querySelector("#linkRows");
const linkProgressBar = document.querySelector("#linkProgressBar");
const linkProgressText = document.querySelector("#linkProgressText");
const linkSearchInput = document.querySelector("#linkSearchInput");
const linkSummary = document.querySelector("#linkSummary");
const duplicateRows = document.querySelector("#duplicateRows");
const operationList = document.querySelector("#operationList");
const issueRows = document.querySelector("#issueRows");
const searchInput = document.querySelector("#searchInput");
const noteInput = document.querySelector("#noteInput");
const saveButton = document.querySelector("#saveButton");
const exportButton = document.querySelector("#exportButton");
const saveStatus = document.querySelector("#saveStatus");
const refreshButton = document.querySelector("#refreshButton");
const stepButtons = Array.from(document.querySelectorAll("[data-view]"));
const panels = Array.from(document.querySelectorAll("[data-panel]"));

workspacePath.textContent = window.__BOOKMARK_WORKSPACE__;
if (window.__BOOKMARK_SERVER__?.url) {
  serverUrl.textContent = window.__BOOKMARK_SERVER__.url;
  serverUrl.href = window.__BOOKMARK_SERVER__.url;
}
if (window.__BOOKMARK_SERVER__?.shutdownAfterSeconds > 0) {
  const expiresAt = window.__BOOKMARK_SERVER__.expiresAt
    ? new Date(window.__BOOKMARK_SERVER__.expiresAt).toLocaleString()
    : "";
  serverTtl.textContent = expiresAt ? `${expiresAt} 自动关闭` : "临时服务会自动关闭";
} else {
  serverTtl.textContent = "自动关闭未启用";
}

/**
 * 渲染一个摘要指标。
 *
 * @param {string} label 指标名称。
 * @param {number|string} value 指标值。
 * @returns {string} 指标 HTML。
 */
function metric(label, value) {
  return `<div class="metric"><span class="muted">${label}</span><span class="metric-value">${value}</span></div>`;
}

/**
 * 转义动态文本，避免把书签标题或 URL 当作 HTML 执行。
 *
 * @param {unknown} value 原始值。
 * @returns {string} 已转义文本。
 */
function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/**
 * 从分析结果构造统一待处理项列表。
 *
 * @param {object} analysis 后端返回的分析数据。
 * @returns {Array<object>} 待处理项列表。
 */
function buildIssues(analysis) {
  const issues = [];
  for (const item of analysis.suspiciousTitles || []) {
    issues.push({
      id: `title:${item.bookmark.order}`,
      type: "可疑标题",
      title: item.bookmark.title || "(空标题)",
      url: item.bookmark.url,
      folder: item.bookmark.folderDisplayPath,
      status: item.reason,
      level: "warn",
    });
  }
  for (const folder of analysis.emptyFolders || []) {
    issues.push({
      id: `folder:${folder.displayPath}`,
      type: "空文件夹",
      title: folder.displayPath,
      url: "",
      folder: folder.displayPath,
      status: "empty_folder",
      level: "warn",
    });
  }
  for (const folder of analysis.dedupAtRiskFolders || []) {
    issues.push({
      id: `dedup:${folder.displayPath}`,
      type: "去重风险",
      title: folder.displayPath,
      url: "",
      folder: folder.displayPath,
      status: "dedup_at_risk",
      level: "warn",
    });
  }
  for (const group of analysis.duplicates || []) {
    issues.push({
      id: `duplicate:${group.normalizedUrl}`,
      type: "重复 URL",
      title: group.normalizedUrl,
      url: `${group.count} 个重复项`,
      folder: "多个目录",
      status: "duplicate_group",
      level: "warn",
    });
  }
  for (const item of analysis.linkChecks?.items || []) {
    if (item.errorCategory || item.skippedReason === "context_required" || (item.statusCode && item.statusCode >= 400)) {
      const needsContext = item.skippedReason === "context_required";
      issues.push({
        id: `link:${item.order}`,
        type: needsContext ? "上下文链接" : "链接异常",
        title: item.title,
        url: item.url,
        folder: item.folderDisplayPath,
        status: item.networkHint || item.bucket,
        level: needsContext ? "warn" : "danger",
      });
    }
  }
  return issues;
}

/**
 * 提取需要用户关注的链接检测结果。
 *
 * @param {object} analysis 后端返回的分析数据。
 * @returns {Array<object>} 链接问题列表。
 */
function buildLinkItems(analysis) {
  return (analysis.linkChecks?.items || []).filter((item) =>
    item.errorCategory || item.skippedReason === "context_required" || (item.statusCode && item.statusCode >= 400)
  );
}

/**
 * 渲染顶部摘要指标。
 *
 * @returns {void}
 */
function renderSummary() {
  const summary = state.analysis.summary;
  const status = state.analysis.workspaceStatus || {};
  summaryGrid.innerHTML = [
    metric("书签", status.bookmarkCount ?? summary.bookmarkCount),
    metric("文件夹", status.folderCount ?? summary.folderCount),
    metric("最大深度", summary.maxDepth),
    metric("重复组", summary.duplicateGroupCount),
    metric("操作", status.operationCount ?? 0),
  ].join("");
}

/**
 * 渲染总览阶段和下一步提示。
 *
 * @returns {void}
 */
function renderOverview() {
  const issues = buildIssues(state.analysis);
  const currentTree = state.analysis.currentTree;
  const hasTree = Boolean(currentTree?.folders?.length);
  const linkCheckEnabled = Boolean(state.analysis.linkChecks?.enabled);
  nextActionText.textContent = hasTree
    ? "先确认目录结构，再让 agent 按批次生成移动/重命名操作。"
    : "当前只有分析报告，请先生成 workspace snapshot。";
  actionGrid.innerHTML = [
    actionCard("1. 设计目录树", hasTree ? "查看目录结构，优先复用原目录，只对混乱、重复、过深的目录生成操作。" : "需要先完成 analyze workspace。"),
    actionCard("2. 处理问题链接", linkCheckEnabled ? "查看异常、私网或上下文依赖链接；默认不把私网链接当死链。" : "尚未启用链接检测，需要用户同意后重新运行 --check-links。"),
    actionCard("3. 批量分配链接", issues.length ? `当前有 ${issues.length} 个待关注项，可先勾选重点。` : "暂无明显问题项，可进入目录和导出检查。"),
  ].join("");
}

/**
 * 渲染一个行动建议卡片。
 *
 * @param {string} title 行动标题。
 * @param {string} body 行动说明。
 * @returns {string} 卡片 HTML。
 */
function actionCard(title, body) {
  return `<div class="action-card"><strong>${escapeHtml(title)}</strong><p>${escapeHtml(body)}</p></div>`;
}

/**
 * 生成目录路径的唯一字符串 key。
 *
 * @param {Array<string>} path 路径数组。
 * @returns {string} 逗号分隔的 key。
 */
function pathKey(path) {
  return path.join(",");
}

/**
 * 递归渲染目录树节点。
 *
 * @param {object} node 后端返回的嵌套树节点。
 * @param {number} depth 当前缩进层级。
 * @returns {string} 节点 HTML。
 */
function renderTreeNode(node, depth) {
  const pk = pathKey(node.path);
  const isExpanded = expandedFolders.get(pk) ?? false;
  const hasChildren = node.children.length > 0 || node.bookmarks.length > 0;
  const arrowClass = hasChildren ? (isExpanded ? "arrow open" : "arrow") : "arrow leaf";
  const indent = "margin-left:" + (depth * 16) + "px;";

  let html = `<div class="tree-node" data-path="${escapeHtml(pk)}">`;
  html += `<div class="tree-toggle ${isExpanded ? "open" : ""}" style="${indent}" data-path="${escapeHtml(pk)}">`;
  html += `<span class="${arrowClass}">&#9654;</span>`;
  html += `<span class="tree-folder-name">${escapeHtml(node.name)}</span>`;
  if (node.bookmarkCount > 0) {
    html += `<span class="badge">${node.bookmarkCount} 个书签</span>`;
  }
  html += `</div>`;

  if (isExpanded && hasChildren) {
    html += `<div class="tree-children">`;
    const maxShow = 20;
    const bms = node.bookmarks;
    const showAll = expandedFolders.get(pk + ":showAll") ?? false;
    const displayed = showAll ? bms : bms.slice(0, maxShow);
    for (const bm of displayed) {
      html += `<div class="tree-bookmark" style="${indent}">`;
      html += `<a href="${escapeHtml(bm.url)}" target="_blank" rel="noopener">${escapeHtml(bm.title || bm.url)}</a>`;
      html += `</div>`;
    }
    if (!showAll && bms.length > maxShow) {
      html += `<div class="tree-show-more" style="${indent}" data-show-more="${escapeHtml(pk)}">显示更多 (${bms.length - maxShow} 个)...</div>`;
    }
    for (const child of node.children) {
      html += renderTreeNode(child, depth + 1);
    }
    html += `</div>`;
  }

  html += `</div>`;
  return html;
}

/**
 * 渲染 replay 后的当前目录树（可折叠版本）。
 *
 * @returns {void}
 */
function renderTree() {
  const tree = state.analysis.currentTree?.tree;
  if (!tree || !tree.children || tree.children.length === 0) {
    treeList.innerHTML = `<p class="muted">暂无 current-tree.json，请重新运行 analyze 或 apply-ops。</p>`;
    return;
  }
  treeList.innerHTML = tree.children.map((child) => renderTreeNode(child, 0)).join("");
}

/**
 * 处理目录树点击事件（折叠展开 + 显示更多）。
 *
 * @param {Event} event 点击事件。
 * @returns {void}
 */
function handleTreeClick(event) {
  const toggle = event.target.closest(".tree-toggle");
  if (toggle) {
    const pk = toggle.dataset.path;
    expandedFolders.set(pk, !expandedFolders.get(pk));
    renderTree();
    return;
  }
  const showMore = event.target.closest("[data-show-more]");
  if (showMore) {
    expandedFolders.set(showMore.dataset.showMore + ":showAll", true);
    renderTree();
  }
}

/**
 * 渲染链接检测状态摘要条（可点击筛选）。
 *
 * @returns {void}
 */
function renderLinkSummary() {
  const linkChecks = state.analysis.linkChecks;
  if (!linkChecks?.enabled) {
    linkSummary.innerHTML = `<span class="muted">尚未启用链接检测。</span>`;
    return;
  }
  const summary = linkChecks.summary || {};
  const entries = Object.entries(summary);
  const active = state.linkFilter || "";
  // "全部"按钮
  let html = `<span class="badge ${!active ? "active" : ""} link-filter-badge" data-filter="">全部</span>`;
  html += entries
    .map(([key, count]) => {
      const level = key.includes("error") || key.includes("4xx") || key.includes("5xx") ? "danger" : key.includes("skipped") ? "warn" : "ok";
      const isActive = active === key ? " active" : "";
      return `<span class="badge ${level}${isActive} link-filter-badge" data-filter="${escapeHtml(key)}">${escapeHtml(key)}: ${count}</span>`;
    })
    .join(" ");
  linkSummary.innerHTML = html;
}

/**
 * 渲染链接检测进度条。
 *
 * @returns {void}
 */
function renderLinkProgress() {
  if (!linkProgressBar || !linkProgressText) return;
  const progress = state.linkProgress;
  if (!progress || !progress.running) {
    linkProgressBar.classList.add("hidden");
    if (progress && progress.percent >= 100) {
      linkProgressText.textContent = "链接检测已完成";
    } else {
      linkProgressText.textContent = "";
    }
    return;
  }
  linkProgressBar.classList.remove("hidden");
  const percent = Math.round(progress.percent);
  linkProgressBar.innerHTML = `<div class="progress-fill" style="width:${percent}%"></div>`;
  linkProgressText.textContent = `检测中... ${progress.done}/${progress.total} (${percent}%)`;
}

// 链接分页
let linkPage = 0;
const LINK_PAGE_SIZE = 50;

/**
 * 渲染链接状态阶段（分页 + 可点击 + 筛选）。
 *
 * @returns {void}
 */
function renderLinks() {
  const linkChecks = state.analysis.linkChecks;
  if (!linkChecks?.enabled) {
    linkRows.innerHTML = `<tr><td colspan="5">尚未启用链接检测；需要用户明确同意后重新运行 --check-links。</td></tr>`;
    return;
  }
  const keyword = (state.linkSearch || "").trim().toLowerCase();
  const filter = state.linkFilter || "";
  const allItems = linkChecks.items || [];

  const filtered = allItems.filter((item) => {
    // 状态标签筛选
    if (filter) {
      const bucket = item.bucket || "";
      if (bucket !== filter) return false;
    }
    // 搜索筛选
    if (keyword) {
      const haystack = `${item.title} ${item.url} ${item.folderDisplayPath || ""} ${item.bucket || ""} ${item.errorCategory || ""} ${item.statusCode || ""}`.toLowerCase();
      if (!haystack.includes(keyword)) return false;
    }
    // 默认只显示有问题的
    if (!keyword && !filter) {
      const isProblem = item.errorCategory || item.skippedReason === "context_required" || (item.statusCode && item.statusCode >= 400);
      if (!isProblem) return false;
    }
    return true;
  });

  const totalPages = Math.ceil(filtered.length / LINK_PAGE_SIZE);
  linkPage = Math.min(linkPage, Math.max(0, totalPages - 1));
  const start = linkPage * LINK_PAGE_SIZE;
  const pageItems = filtered.slice(start, start + LINK_PAGE_SIZE);

  linkRows.innerHTML = pageItems.map((item) => {
    const needsContext = item.skippedReason === "context_required";
    const level = needsContext ? "warn" : "danger";
    return `
      <tr>
        <td><span class="badge ${level}">${escapeHtml(item.bucket || item.errorCategory || item.statusCode || "unknown")}</span></td>
        <td class="title-cell">
          <a href="${escapeHtml(item.url)}" target="_blank" rel="noopener"><strong>${escapeHtml(item.title)}</strong></a>
          <a href="${escapeHtml(item.finalUrl || item.url)}" target="_blank" rel="noopener" class="url mono">${escapeHtml(item.finalUrl || item.url)}</a>
        </td>
        <td>${escapeHtml(item.folderDisplayPath || "")}</td>
        <td>${escapeHtml(item.networkHint || "")}</td>
        <td>${item.elapsedMs || 0}ms</td>
      </tr>
    `;
  }).join("") || `<tr><td colspan="5">没有匹配的链接。</td></tr>`;

  // 分页控制
  const pagination = document.getElementById("linkPagination");
  if (pagination) {
    pagination.innerHTML = filtered.length > LINK_PAGE_SIZE
      ? `<span class="muted">显示 ${start + 1}-${Math.min(start + LINK_PAGE_SIZE, filtered.length)} / 共 ${filtered.length} 条</span>
         <div class="pagination-buttons">
           <button class="button ghost" ${linkPage <= 0 ? "disabled" : ""} data-link-page="${linkPage - 1}">上一页</button>
           <span class="muted">${linkPage + 1} / ${totalPages}</span>
           <button class="button ghost" ${linkPage >= totalPages - 1 ? "disabled" : ""} data-link-page="${linkPage + 1}">下一页</button>
         </div>`
      : `<span class="muted">共 ${filtered.length} 条</span>`;
  }
}

/**
 * 渲染重复 URL 阶段。
 *
 * @returns {void}
 */
function renderDuplicates() {
  const duplicates = state.analysis.duplicates || [];
  duplicateRows.innerHTML = duplicates.map((group) => {
    const folders = (group.items || []).map((item) => item.folderDisplayPath).join(", ");
    return `
      <tr>
        <td class="title-cell"><span class="url mono">${escapeHtml(group.normalizedUrl)}</span></td>
        <td>${escapeHtml(group.count)}</td>
        <td>${escapeHtml(folders)}</td>
      </tr>
    `;
  }).join("") || `<tr><td colspan="3">没有重复 URL 组。</td></tr>`;
}

/**
 * 渲染已批准 operation 与导出阶段。
 *
 * @returns {void}
 */
function renderOperations() {
  const operations = state.analysis.operations || [];
  const reversed = [...operations].reverse();
  operationList.innerHTML = reversed.map((op, i) => {
    const idx = operations.length - i;
    const phaseLabel = op.phase ? `<span class="badge">${escapeHtml(op.phase)}</span>` : "";
    const statusBadge = op.approved === false
      ? `<span class="badge warn">未批准</span>`
      : `<span class="badge ok">已批准</span>`;
    const detail = formatOpDetail(op);
    return `
    <div class="operation-row">
      <div class="op-main">
        <div class="op-header">
          <span class="op-index">#${idx}</span>
          <strong>${escapeHtml(op.op)}</strong>
          ${phaseLabel}
          ${statusBadge}
        </div>
        <div class="op-detail">${detail}</div>
        ${op.reason ? `<div class="op-reason muted">${escapeHtml(op.reason)}</div>` : ""}
      </div>
    </div>`;
  }).join("") || `<p class="muted">暂无已批准操作。先让 agent 生成 operations，再用 CLI apply-ops 写入。</p>`;
  // 更新导航标签上的计数
  const opsStep = document.querySelector('[data-view="operations"]');
  if (opsStep) {
    opsStep.textContent = `5. 操作与导出 (${operations.length})`;
  }
}

/**
 * 格式化单个 operation 的详细路径/书签信息。
 *
 * @param {object} op - operation 对象
 * @returns {string} HTML 字符串
 */
function formatOpDetail(op) {
  const pathStr = (arr) => (arr || []).join(" / ") || "根目录";
  switch (op.op) {
    case "move_folder":
      return `<span class="mono">${escapeHtml(pathStr(op.fromPath))}</span> → <span class="mono">${escapeHtml(pathStr(op.toPath))}</span>`;
    case "create_folder":
      return `<span class="mono">${escapeHtml(pathStr(op.path))}</span>`;
    case "delete_empty_folder":
      return `<span class="mono">${escapeHtml(pathStr(op.path))}</span>`;
    case "rename_folder":
      return `<span class="mono">${escapeHtml(pathStr(op.fromPath))}</span> → <span class="mono">${escapeHtml(pathStr(op.toPath))}</span>`;
    case "move_bookmark":
      return `书签 <code>${escapeHtml(op.bookmarkId || "")}</code> → <span class="mono">${escapeHtml(pathStr(op.toPath))}</span>`;
    case "archive_bookmark":
      return `书签 <code>${escapeHtml(op.bookmarkId || "")}</code> → <span class="mono">${escapeHtml(pathStr(op.toPath || ["_Archive"]))}</span>`;
    case "rename_bookmark":
      return `书签 <code>${escapeHtml(op.bookmarkId || "")}</code> → ${escapeHtml(op.title || "")}`;
    case "update_url":
      return `书签 <code>${escapeHtml(op.bookmarkId || "")}</code>`;
    case "mark_bookmark":
      return `书签 <code>${escapeHtml(op.bookmarkId || "")}</code> 标记: ${escapeHtml(op.mark || "")}`;
    default:
      return `<span class="mono">${escapeHtml(JSON.stringify(op))}</span>`;
  }
}

/**
 * 渲染可搜索的待处理项表格。
 *
 * @returns {void}
 */
function renderIssues() {
  const keyword = searchInput.value.trim().toLowerCase();
  const issues = buildIssues(state.analysis).filter((item) => {
    const haystack = `${item.type} ${item.title} ${item.url} ${item.folder} ${item.status}`.toLowerCase();
    return !keyword || haystack.includes(keyword);
  });

  issueRows.innerHTML = issues.map((item) => `
    <tr>
      <td><input type="checkbox" data-id="${escapeHtml(item.id)}" ${state.decisions.selected[item.id] ? "checked" : ""}></td>
      <td>${escapeHtml(item.type)}</td>
      <td class="title-cell">
        <strong>${escapeHtml(item.title)}</strong>
        <span class="url mono">${escapeHtml(item.url)}</span>
      </td>
      <td>${escapeHtml(item.folder)}</td>
      <td><span class="badge ${item.level}">${escapeHtml(item.status)}</span></td>
    </tr>
  `).join("") || `<tr><td colspan="5">当前过滤条件下没有待处理项。</td></tr>`;
}

/**
 * 切换当前阶段面板。
 *
 * @returns {void}
 */
function renderActivePanel() {
  panels.forEach((panel) => {
    panel.classList.toggle("hidden", panel.dataset.panel !== state.activeView);
  });
  stepButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.view === state.activeView);
  });
  if (summaryGrid) {
    summaryGrid.classList.toggle("hidden", state.activeView !== "overview");
  }
}

/**
 * 渲染完整工作台状态。
 *
 * @returns {void}
 */
function render() {
  renderSummary();
  renderOverview();
  renderTree();
  renderLinkProgress();
  renderLinkSummary();
  renderLinks();
  renderDuplicates();
  renderOperations();
  renderIssues();
  renderActivePanel();
}

/**
 * 加载 workspace 分析数据和已保存选择。
 *
 * @returns {Promise<void>} 数据加载完成后 resolve。
 */
async function loadData() {
  const [analysisRes, decisionsRes] = await Promise.all([
    fetch("/api/analysis"),
    fetch("/api/decisions"),
  ]);
  state.analysis = await analysisRes.json();
  const decisionPayload = await decisionsRes.json();
  state.decisions = decisionPayload.decisions || { selected: {}, note: "" };
  state.decisions.selected ||= {};
  noteInput.value = state.decisions.note || "";
  lastOperationCount = state.analysis.workspaceStatus?.operationCount ?? 0;
  render();
  startPolling();
}

// ---- ops 状态同步（轮询） ----

/**
 * 拉取最新分析数据，检测变化后刷新。
 *
 * @returns {Promise<void>}
 */
async function pollAnalysis() {
  try {
    const res = await fetch("/api/analysis");
    if (!res.ok) return;
    const data = await res.json();
    const newCount = data.workspaceStatus?.operationCount ?? 0;
    const linkEnabled = Boolean(data.linkChecks?.enabled);
    const prevLinkEnabled = Boolean(state.analysis?.linkChecks?.enabled);
    // 操作数变化、链接检测从无到有、数据变化时都刷新
    if (newCount !== lastOperationCount || (linkEnabled && !prevLinkEnabled)) {
      lastOperationCount = newCount;
      state.analysis = data;
      render();
    }
  } catch {
    // 网络错误静默忽略
  }
}

/**
 * 拉取链接检测进度。
 *
 * @returns {Promise<void>}
 */
async function pollLinkProgress() {
  try {
    const res = await fetch("/api/link-progress");
    if (!res.ok) return;
    const data = await res.json();
    state.linkProgress = data;
    renderLinkProgress();
    // 检测完成后自动刷新分析数据
    if (!data.running && state.analysis?.linkChecks && !state.analysis.linkChecks.enabled) {
      await pollAnalysis();
    }
  } catch {
    // 静默忽略
  }
}

/**
 * 启动轮询定时器。
 *
 * @returns {void}
 */
function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(pollAnalysis, POLL_INTERVAL);
  linkPollTimer = setInterval(pollLinkProgress, LINK_POLL_INTERVAL);
}

/**
 * 停止轮询定时器。
 *
 * @returns {void}
 */
function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  if (linkPollTimer) {
    clearInterval(linkPollTimer);
    linkPollTimer = null;
  }
}

// 页面可见性控制
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    stopPolling();
  } else {
    pollAnalysis();
    pollLinkProgress();
    startPolling();
  }
});

// ---- 事件绑定 ----

stepButtons.forEach((button) => {
  button.addEventListener("click", () => {
    state.activeView = button.dataset.view;
    renderActivePanel();
    document.querySelector(".workspace")?.scrollIntoView({ block: "start" });
  });
});

treeList.addEventListener("click", handleTreeClick);

issueRows.addEventListener("change", (event) => {
  if (event.target.matches("input[type='checkbox']")) {
    state.decisions.selected[event.target.dataset.id] = event.target.checked;
  }
});

searchInput.addEventListener("input", renderIssues);

if (linkSearchInput) {
  linkSearchInput.addEventListener("input", () => {
    state.linkSearch = linkSearchInput.value;
    linkPage = 0;
    renderLinks();
  });
}

// 链接状态标签筛选
if (linkSummary) {
  linkSummary.addEventListener("click", (event) => {
    const badge = event.target.closest("[data-filter]");
    if (!badge) return;
    const filter = badge.dataset.filter;
    state.linkFilter = state.linkFilter === filter ? "" : filter;
    linkPage = 0;
    renderLinkSummary();
    renderLinks();
  });
}

// 链接分页按钮
document.addEventListener("click", (event) => {
  const btn = event.target.closest("[data-link-page]");
  if (!btn || btn.disabled) return;
  linkPage = parseInt(btn.dataset.linkPage, 10);
  renderLinks();
});

saveButton.addEventListener("click", async () => {
  state.decisions.note = noteInput.value;
  saveStatus.textContent = "正在保存...";
  const response = await fetch("/api/decisions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ decisions: state.decisions }),
  });
  if (!response.ok) {
    saveStatus.textContent = "保存失败，请查看 review-server.log。";
    return;
  }
  const result = await response.json();
  saveStatus.textContent = `已保存到 ${result.path}`;
});

exportButton.addEventListener("click", async () => {
  saveStatus.textContent = "正在导出...";
  const response = await fetch("/api/export", { method: "POST" });
  if (!response.ok) {
    saveStatus.textContent = "导出失败，请查看 review-server.log。";
    return;
  }
  const result = await response.json();
  saveStatus.textContent = `已导出到 ${result.path}`;
});

if (refreshButton) {
  refreshButton.addEventListener("click", async () => {
    saveStatus.textContent = "刷新中...";
    await pollAnalysis();
    await pollLinkProgress();
    saveStatus.textContent = "已刷新";
  });
}

loadData().catch((error) => {
  saveStatus.textContent = `加载失败：${error.message}`;
});
