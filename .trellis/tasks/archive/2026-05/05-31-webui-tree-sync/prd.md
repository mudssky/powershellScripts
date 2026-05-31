# WebUI 可折叠目录树与 ops 状态同步

## Goal

改进 browser-bookmark-organizer 的 Review WebUI，使目录树以可折叠方式展示，并在 CLI 追加 ops 后前端能自动刷新到最新状态。

## Background

当前 WebUI 的目录树（tree 视图）将所有文件夹一次性平铺展开，对 600+ 文件夹的书签集不友好；此外，当 agent 通过 CLI `apply-ops` 追加操作后，前端页面仍显示旧状态，需手动刷新浏览器。

## Requirements

### R1: 可折叠目录树

- 目录树初始只展开第一层，深层文件夹默认折叠。
- 点击文件夹行可展开/折叠其子文件夹和直属书签。
- 折叠状态由用户控制，不随数据刷新重置。
- 每个文件夹行显示：文件夹名、直属书签数、展开/折叠箭头图标。
- 展开后子文件夹缩进显示，直属书签以链接形式列出（标题 + URL）。

### R2: ops 后状态同步

- 前端定期轮询 `/api/analysis`（间隔 5 秒），检测 operationCount 变化。
- 检测到新 operation 时自动重新渲染目录树、摘要指标和操作列表。
- 轮询可在页面不可见时暂停（`visibilitychange`），恢复可见时立即拉取一次。
- 提供手动刷新按钮作为后备。

## Acceptance Criteria

- [ ] 目录树默认折叠，只显示第一层文件夹
- [ ] 点击文件夹可展开/折叠，图标有方向变化
- [ ] 展开文件夹后可见子文件夹和直属书签
- [ ] CLI apply-ops 后 5 秒内 WebUI 自动反映最新状态
- [ ] 页面不可见时暂停轮询，可见时恢复
- [ ] 手动刷新按钮可用
- [ ] 折叠状态不因数据刷新被重置

## Constraints

- 纯前端实现，不引入额外 JS 依赖（无 React/Vue 等）。
- 后端 API 需为目录树提供层级结构（parent-children），当前 `/api/analysis` 返回的 `currentTree.folders` 是扁平列表，需改为嵌套结构或提供足够信息让前端构建树。
- 所有改动在 `review.js`、`review.css`、`review_server.py`、`state.py` 内完成。
