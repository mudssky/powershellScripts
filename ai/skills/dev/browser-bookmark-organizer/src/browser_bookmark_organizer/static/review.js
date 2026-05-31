const state = {
  activeView: "overview",
  analysis: null,
  decisions: { selected: {}, note: "" },
};

const workspacePath = document.querySelector("#workspacePath");
const serverUrl = document.querySelector("#serverUrl");
const serverTtl = document.querySelector("#serverTtl");
const nextActionText = document.querySelector("#nextActionText");
const summaryGrid = document.querySelector("#summaryGrid");
const actionGrid = document.querySelector("#actionGrid");
const treeList = document.querySelector("#treeList");
const linkRows = document.querySelector("#linkRows");
const duplicateRows = document.querySelector("#duplicateRows");
const operationList = document.querySelector("#operationList");
const issueRows = document.querySelector("#issueRows");
const searchInput = document.querySelector("#searchInput");
const noteInput = document.querySelector("#noteInput");
const saveButton = document.querySelector("#saveButton");
const exportButton = document.querySelector("#exportButton");
const saveStatus = document.querySelector("#saveStatus");
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
 * 根据目录深度生成可读缩进。
 *
 * @param {number} depth 目录深度。
 * @returns {string} HTML 空格缩进。
 */
function folderIndent(depth) {
  return "&nbsp;".repeat(Math.max(0, depth - 1) * 4);
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
 * 渲染 replay 后的当前目录树。
 *
 * @returns {void}
 */
function renderTree() {
  const folders = state.analysis.currentTree?.folders || [];
  treeList.innerHTML = folders.map((folder) => `
    <div class="tree-row">
      <span class="tree-path">${folderIndent(folder.depth)}${escapeHtml(folder.displayPath)}</span>
      <span class="badge">${escapeHtml(folder.directBookmarkCount)} 个直属书签</span>
    </div>
  `).join("") || `<p class="muted">暂无 current-tree.json，请重新运行 analyze 或 apply-ops。</p>`;
}

/**
 * 渲染链接状态阶段。
 *
 * @returns {void}
 */
function renderLinks() {
  const items = buildLinkItems(state.analysis);
  if (!state.analysis.linkChecks?.enabled) {
    linkRows.innerHTML = `<tr><td colspan="4">尚未启用链接检测；需要用户明确同意后重新运行 --check-links。</td></tr>`;
    return;
  }
  linkRows.innerHTML = items.map((item) => {
    const needsContext = item.skippedReason === "context_required";
    const level = needsContext ? "warn" : "danger";
    return `
      <tr>
        <td>${needsContext ? "上下文链接" : "链接异常"}</td>
        <td class="title-cell">
          <strong>${escapeHtml(item.title)}</strong>
          <span class="url mono">${escapeHtml(item.url)}</span>
        </td>
        <td>${escapeHtml(item.folderDisplayPath)}</td>
        <td><span class="badge ${level}">${escapeHtml(item.networkHint || item.bucket || item.errorCategory || item.statusCode)}</span></td>
      </tr>
    `;
  }).join("") || `<tr><td colspan="4">没有需要关注的链接状态。</td></tr>`;
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
  operationList.innerHTML = operations.map((operation) => `
    <div class="operation-row">
      <span>
        <strong>${escapeHtml(operation.op)}</strong>
        <span class="muted"> ${escapeHtml(operation.reason || operation.phase || "")}</span>
      </span>
      <span class="badge ${operation.approved === false ? "warn" : "ok"}">${operation.approved === false ? "未批准" : "已批准"}</span>
    </div>
  `).join("") || `<p class="muted">暂无已批准操作。先让 agent 生成 operations，再用 CLI apply-ops 写入。</p>`;
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
  render();
}

stepButtons.forEach((button) => {
  button.addEventListener("click", () => {
    state.activeView = button.dataset.view;
    renderActivePanel();
  });
});

issueRows.addEventListener("change", (event) => {
  if (event.target.matches("input[type='checkbox']")) {
    state.decisions.selected[event.target.dataset.id] = event.target.checked;
  }
});

searchInput.addEventListener("input", renderIssues);

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

loadData().catch((error) => {
  saveStatus.textContent = `加载失败：${error.message}`;
});
