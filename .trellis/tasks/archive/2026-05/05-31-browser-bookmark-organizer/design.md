# 浏览器书签整理技能设计

## Scope

在 `ai/skills/dev/browser-bookmark-organizer/` 创建独立 skill，提供一个可复现运行的 Python/uv CLI：

- 默认离线解析 Netscape Bookmark HTML，写入 workspace，并启动本地临时 WebUI；Markdown/HTML 报告与 JSON 数据作为副产物保留。
- 显式传入 `--check-links` 时才联网检测链接，使用 HTTPX。
- 默认不修改原始书签 HTML，不生成可导入的新书签文件。
- 使用 run workspace 保存分析结果、报告、用户选择和后续操作日志，不把用户数据写到 skill 目录。
- 提供本地 FastAPI WebUI 服务，用户在浏览器里查看实时状态、审核并提交选择，服务只绑定 `127.0.0.1`，默认后台启动并在 1 小时后自动关闭。
- 不提交用户的 `ai/skills/bookmarks_31_05_2026.html`；测试使用脱敏极小 fixture。

## Architecture

```text
browser-bookmark-organizer/
  SKILL.md
  pyproject.toml
  uv.lock
  src/browser_bookmark_organizer/
    cli.py
    clock.py
    workspace.py
    templating.py
    review_server.py
    parser.py
    analysis.py
    link_checker.py
    report.py
    models.py
    templates/
      review.html
      report.html
    static/
      review.css
      review.js
      report.css
  tests/
    fixtures/sample_bookmarks.html
    test_analysis.py
    test_cli.py
    test_link_checker.py
    test_parser.py
  references/
    workflow.md
```

## Data Flow

1. `parser.py` 使用标准库 `html.parser.HTMLParser` 解析 Netscape Bookmark HTML。
2. `analysis.py` 展平目录树并计算统计信息、重复 URL、空目录和疑似异常标题。
3. `link_checker.py` 在 `--check-links` 时使用 `httpx.AsyncClient` 并发检测 HTTP/HTTPS URL。
4. `templating.py` 使用 Jinja2 `PackageLoader` 读取包内模板，并启用 HTML 自动转义。
5. `report.py` 将分析结果渲染为 Markdown、HTML 和 JSON 友好结构；HTML 结构放在 `templates/report.html`，样式放在 `static/report.css`。
6. `workspace.py` 负责 workspace 文件命名、读写和状态落盘。
7. `review_server.py` 从 workspace 读取 `analysis.json` / 后续 `snapshot.json` + `operations.jsonl` 派生当前状态，并保存 `decisions.json`；WebUI HTML/CSS/JS 分别放在 `templates/review.html`、`static/review.css`、`static/review.js`。
8. `clock.py` 统一生成本地时区时间戳，默认使用系统时区，便于以后集中调整。
9. `cli.py` 只负责参数解析、文件 IO、调用流程和退出码。

依赖：

- `httpx`：显式链接检测。
- `fastapi` / `uvicorn`：本地临时 WebUI。
- `jinja2`：渲染包内 HTML 模板，避免把大段 HTML/CSS/JS 直接塞进 Python 文件。

## State Model Direction

当前实现先输出 `analysis.json`，后续整理执行层应演进为 append-only operation 模型：

```text
workspace/
  snapshot.json        # 原始解析数据，只读
  link-checks.json     # 检测证据，不直接改变状态
  operations.jsonl     # 所有已批准操作，append-only
  decisions.json       # WebUI 用户选择记录
```

派生文件和视图：

```text
current-tree.json      # snapshot + operations replay 得到
tree-context.md        # 给 agent 的目录上下文摘要
bookmark-report.html   # 当前状态报告
bookmarks.cleaned.html # 最终导出的新书签 HTML
```

目录树不作为独立真相源。新增目录、重命名、移动、删除空目录等也用 operations 表达；执行完目录操作后，CLI 从当前状态生成新的 tree。

## Organizing Phases

操作日志使用统一 `operations.jsonl`，通过 `phase` 区分阶段：

- `snapshot_evidence`：原始解析、链接检测等证据，不改变状态。
- `dead_link_triage`：废弃链接处理。默认 `mark_bookmark` 或移动到归档目录，不自动删除。
- `tree_restructure`：新目录结构。只做 `create_folder`、`rename_folder`、`move_folder`、`delete_empty_folder`、`merge_folder` 等目录操作。
- `bookmark_assignment`：按新目录批量分配链接。主要做 `move_bookmark`、`rename_bookmark`、`merge_duplicate`、`archive_bookmark`。
- `final_review`：最终批准、拒绝、替代或撤销操作。

检测结果不是 operation；用户或 agent 基于检测证据做出的处理决定才是 operation。

## CLI Shape

推荐命令：

```bash
uv run python -m browser_bookmark_organizer.cli analyze bookmarks.html --workspace ./bookmark-runs/run-001
uv run python -m browser_bookmark_organizer.cli analyze bookmarks.html --workspace ./bookmark-runs/run-001 --check-links
uv run python -m browser_bookmark_organizer.cli analyze bookmarks.html --workspace ./bookmark-runs/run-001 --no-review
uv run python -m browser_bookmark_organizer.cli tree --workspace ./bookmark-runs/run-001
uv run python -m browser_bookmark_organizer.cli apply-ops --workspace ./bookmark-runs/run-001 --input approved-ops.json
uv run python -m browser_bookmark_organizer.cli status --workspace ./bookmark-runs/run-001
uv run python -m browser_bookmark_organizer.cli export --workspace ./bookmark-runs/run-001 --output bookmarks.cleaned.html
uv run python -m browser_bookmark_organizer.cli review --workspace ./bookmark-runs/run-001 --open
```

`analyze` 默认在完成分析后后台启动 WebUI 并输出 `Review UI: http://127.0.0.1:<port>`、`Review PID` 和 `Review log`；`--shutdown-after` 默认 `3600`，`0` 表示不自动关闭。批处理或测试需要只写文件时使用 `--no-review`。需要调试服务时使用 `--foreground`，此时命令会阻塞在当前终端。

日志契约：

- CLI stdout 只输出 workspace、URL、PID、日志路径、导出路径和错误摘要等即时入口信息。
- WebUI 服务内部事件走 Python `logging`，模块级使用 `logger = logging.getLogger(__name__)`，后台服务写入 `review-server.log`。
- 不用大段手写 `open(...).write(...)` 维护运行日志。

兼容旧版直接入口：

```bash
uv run python -m browser_bookmark_organizer.cli bookmarks.html --output-dir /tmp/bookmark-report
```

## Workspace Files

```text
workspace/
  analysis.json
  snapshot.json
  operations.jsonl
  current-tree.json
  bookmark-report.md
  bookmark-report.html
  decisions.json
  review-server.log
  review-server.pid
  bookmarks.cleaned.html
```

`decisions.json` 只记录用户审核选择，后续再派生 `operations.jsonl` 和可导入的新书签文件。用户真实书签和选择记录属于本地数据，不进入 skill 目录。

## HTML Design

- WebUI 使用安静、密集、可扫描的本地工作台风格。
- WebUI 与静态报告使用 Jinja2 模板和包内静态资源维护；Python 只组织数据和渲染模板，不内联大段 HTML/CSS/JS 字符串。
- 主色：teal `#0D9488`，动作色：orange `#F97316`。
- 背景使用浅灰 `#F8FAFC`，正文 `#0F172A`，弱文本 `#475569`。
- URL、ID 和日志使用等宽字体。
- 表格在移动端使用横向滚动，按钮和表单有可见 focus 状态。
- 状态不只靠颜色表达，必须有文字 badge。
- WebUI 需要全程展示当前书签状态，而不是只在最后审核：
  - 当前目录树：由 snapshot + approved operations replay 得到。
  - 阶段进度：废弃链接处理、新目录结构、链接分配、最终审核。
  - 操作队列：待确认、已批准、已拒绝、已应用。
  - 当前批次：例如一次 50 个待整理书签。
  - 状态摘要：剩余待处理数、冲突数、低置信操作数、上下文依赖链接数。
  - 导出预览：最终将写出的新 bookmarks HTML 摘要。
- WebUI 数据获取应以 API 方式读取当前派生状态，CLI 每次 `apply-ops` 后刷新即可看到变化。后续可加 Server-Sent Events 或轮询做自动刷新。
- WebUI 页面顶部应展示 workspace、服务 URL 和自动关闭时间，避免用户找不到当前入口，也避免后台长期占用。
- WebUI 顶部应紧凑，不能使用会遮挡内容的 sticky 大头部；阶段按钮必须可点击并切换对应视图。
- 首屏应明确下一步动作，例如查看目录树、处理问题链接、生成批量 operations 或导出当前书签 HTML，避免用户进入页面后不知道能做什么。

## Link Checking Policy

- 默认不联网。
- `--check-links` 才发请求。
- 默认跟随重定向，可用 `--no-follow-redirects` 关闭。
- 默认低并发和轻量请求间隔，避免对站点造成压力。
- 记录 HTTP 状态、最终 URL、错误类别、错误信息和耗时。
- 不支持的 scheme 标记为 skipped，不作为失败链接处理。
- 默认识别并跳过局域网、Tailscale 和公司内网候选链接，结果标记为 `skipped:context_required`。
- 私网类链接包括 RFC1918/loopback/link-local 地址、Tailscale `100.64.0.0/10`、`.ts.net`、`.local`、单标签主机名和常见内网后缀。
- 用户显式传入 `--check-private-links` 后才检测私网类链接；`--network-context` 记录本次检测环境，例如 `home`、`office`、`tailscale`。

## Validation

- `uv lock`
- `uv run pytest`
- `uv run python -m browser_bookmark_organizer.cli --help`
- 用脱敏 fixture 生成 Markdown/JSON 报告
- 用脱敏 fixture 生成 HTML 报告
- analyze 默认后台启动 review 服务的参数传递测试
- `--foreground` 启动前台服务的参数传递测试
- review 服务保存 `decisions.json`
- 根目录 `pnpm qa`
