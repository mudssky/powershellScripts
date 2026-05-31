---
name: browser-bookmark-organizer
description: 解析和整理浏览器导出的 Netscape Bookmark HTML，生成书签结构报告、重复项检查、空目录检查、疑似乱码标题检查，并可选检测链接可用性。Use when 用户要求整理浏览器书签、分析 bookmarks.html、清理死链/重复书签/空文件夹，或需要在改写书签前先得到可审阅整理方案。
---

# 浏览器书签整理

## 使用时机

用于分析浏览器导出的 `bookmarks.html` / Netscape Bookmark HTML。默认创建 workspace 并启动本地临时 WebUI，终端必须显示可访问 URL；报告 HTML 只是副产物。默认不修改原始文件，也不生成可导入的新书签文件。

如果用户要“重新分类书签”，先用本 skill 解析和出报告；分类方法、目录树设计、批量操作和审核流程见本 skill 自带的 `references/workflow.md`。本 skill 安装后应独立可用，不依赖其他 skill 的路径或文档。

WebUI 默认后台启动并立即把控制权还给 agent，stdout 会输出 `Review UI`、`Review PID`、`Review log` 和自动关闭时间；需要调试服务时才加 `--foreground` 以前台运行。

## 快速流程

1. 确认输入是浏览器导出的 HTML 文件，不要把用户的原始书签文件提交到仓库。
2. 进入本 skill 根目录。
3. 默认先跑离线分析、写入 workspace，并在后台启动本地临时 WebUI。终端会输出 `Review UI: http://127.0.0.1:<port>`、后台 PID 和日志路径，默认 1 小时后自动关闭：

```bash
uv run python -m browser_bookmark_organizer.cli analyze /path/to/bookmarks.html --workspace ./bookmark-runs/run-001
```

4. 用户明确同意联网检测后，再加 `--check-links`。检测结束后同样进入 WebUI：

```bash
uv run python -m browser_bookmark_organizer.cli analyze /path/to/bookmarks.html --workspace ./bookmark-runs/run-001 --check-links
```

5. 如果已有 workspace，只想重新打开工作台：

```bash
uv run python -m browser_bookmark_organizer.cli review --workspace ./bookmark-runs/run-001 --open
```

`review` 默认同样后台启动；只想在批处理或测试里生成文件，不启动服务时显式使用 `--no-review`。需要让命令阻塞在当前终端用于调试时，加 `--foreground`。

整理过程中查看状态、应用操作和导出：

```bash
uv run python -m browser_bookmark_organizer.cli tree --workspace ./bookmark-runs/run-001
uv run python -m browser_bookmark_organizer.cli apply-ops --workspace ./bookmark-runs/run-001 --input approved-ops.json
uv run python -m browser_bookmark_organizer.cli status --workspace ./bookmark-runs/run-001
uv run python -m browser_bookmark_organizer.cli export --workspace ./bookmark-runs/run-001 --output bookmarks.cleaned.html
```

## CLI 能力

入口命令必须从本 skill 根目录运行。推荐使用子命令：

```bash
uv run python -m browser_bookmark_organizer.cli analyze [options] <bookmarks.html>
uv run python -m browser_bookmark_organizer.cli tree --workspace <dir>
uv run python -m browser_bookmark_organizer.cli apply-ops --workspace <dir> --input <ops.json>
uv run python -m browser_bookmark_organizer.cli status --workspace <dir>
uv run python -m browser_bookmark_organizer.cli export --workspace <dir> --output <bookmarks.cleaned.html>
uv run python -m browser_bookmark_organizer.cli review --workspace <dir>
```

常用参数：

- `--workspace <dir>`：分析结果、报告和用户选择记录目录。
- `--output-dir <dir>`：兼容旧入口；同时输出 `bookmark-report.md`、`bookmark-report.html` 和 `bookmark-report.json`。
- `--markdown-out <file>`：单独指定 Markdown 报告路径。
- `--json-out <file>`：单独指定 JSON 数据路径。
- `--html-out <file>`：单独指定 HTML 报告路径。
- `--review`：分析完成后启动本地 WebUI；无显式输出参数时默认启用。
- `--no-review`：只写入报告和 workspace，不启动 WebUI，适合测试或批处理。
- `--host 127.0.0.1`：WebUI 监听地址，默认只绑定本机。
- `--port 0`：WebUI 监听端口；`0` 表示自动选择空闲端口。
- `--open`：WebUI 启动后自动打开浏览器。
- `--foreground`：以前台方式运行 WebUI；默认后台启动并立即返回，避免 agent 卡在服务进程里。
- `--shutdown-after <seconds>`：WebUI 自动关闭秒数，默认 `3600`；`0` 表示不自动关闭。
- `--check-links`：启用 HTTP/HTTPS 链接检测；默认不联网。
- `--timeout <seconds>`：单个请求超时，默认 `10`。
- `--concurrency <n>`：链接检测并发数，默认 `5`。
- `--delay <seconds>`：请求启动间隔，默认 `0.2`。
- `--no-follow-redirects`：不跟随重定向。
- `--max-links <n>`：只检测前 N 个 HTTP/HTTPS 链接，适合先做小样本。
- `--check-private-links`：显式检测局域网、Tailscale 和公司内网候选链接；默认只标记为需要上下文。
- `--network-context <name>`：记录本次检测环境，例如 `home`、`office`、`tailscale`。
- `review --host 127.0.0.1 --port 0 --open --shutdown-after 3600`：重新打开本地审核页，默认后台启动。
- `review --foreground --log-file <file>`：以前台方式运行，并把服务日志写入指定文件。

`apply-ops` 支持 JSON 数组或 `{ "operations": [...] }`，也支持 JSONL。当前 operation 会追加到 `operations.jsonl`；CLI replay `snapshot.json + operations.jsonl` 得到当前状态。

## 输出内容

workspace 默认包含：

- `analysis.json`：结构化分析数据。
- `snapshot.json`：原始解析快照，只读。
- `operations.jsonl`：已批准操作日志，append-only。
- `current-tree.json`：当前目录树派生数据。
- `bookmark-report.md`：Markdown 报告。
- `bookmark-report.html`：静态 HTML 报告副产物；交互整理以 WebUI URL 为主。
- `decisions.json`：用户在 review 页面提交的选择。
- `review-server.log`：后台 WebUI 服务日志。
- `review-server.pid`：后台 WebUI 服务 PID。
- `bookmarks.cleaned.html`：导出的新书签 HTML。

报告会包含：

- 文件夹数、书签数、最大目录深度。
- URL scheme 与 domain 分布。
- 规范化后重复 URL。
- 空文件夹。
- 空标题与疑似乱码标题。
- 链接检测摘要、失败链接、重定向信息。
- 上下文依赖链接：局域网、Tailscale、公司内网候选；默认不作为死链候选。

## 安全边界

- 默认不联网；`--check-links` 是显式动作。
- 默认不检测私网类链接；`--check-private-links` 是显式动作，适合在公司网络、家庭局域网或 Tailscale 已连接时使用。
- WebUI 默认只绑定 `127.0.0.1`，默认 1 小时自动关闭，避免长期占后台。
- 默认不修改输入 HTML。
- 不把 `ICON` 的 base64 数据写入报告，避免报告膨胀。
- 不把用户选择记录写入 skill 目录；写入用户指定 workspace。
- 不提交用户真实书签导出文件；如需测试，创建脱敏极小 fixture。
- 批量移动、删除、重命名或生成可导入书签文件前，必须先给整理计划并等待用户明确批准。
- 服务日志使用 Python `logging` 与模块级 `logger = logging.getLogger(__name__)`；CLI 只把 URL、PID、日志路径、导出路径等关键入口信息输出到 stdout。
- 时间戳走包内统一时间封装，默认使用系统本地时区，便于以后集中调整时区策略。

## 参考

- 书签整理工作流和分类建议：读 `references/workflow.md`。
