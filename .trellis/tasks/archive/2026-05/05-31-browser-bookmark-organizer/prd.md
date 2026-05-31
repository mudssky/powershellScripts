# 创建浏览器书签整理技能

## Goal

在 `ai/skills/dev` 下创建一个浏览器书签整理 skill，帮助 agent 解析浏览器导出的 Netscape Bookmark HTML，统计书签结构、检测链接状态、识别重复和可疑项，并输出可审阅的整理方案。

用户价值：

- 面对多年积累的浏览器书签时，先获得结构化报告，而不是直接手工翻文件夹。
- 能发现死链、重定向、超时、疑似重复、空目录、乱码标题和过深目录。
- 能使用本 skill 内置的书签分类方法论给出整理建议，但不直接篡改原始书签文件。

## Confirmed Facts

- 用户希望新开一个独立书签整理 skill，而不是把功能叠加到其他整理 skill。
- 用户倾向 Python 实现；链接检测可以声明 `httpx` 依赖。
- 已用 Context7 查询 HTTPX，确认 `/encode/httpx` 是 Python HTTPX；HTTPX 支持 timeout、redirect 控制、client 默认 timeout 和异常分类，适合链接检测。
- 目标应是脚本型 skill，而不是纯文档 skill，因为需要解析 HTML 和发送请求检测网页可用性。
- `ai/skills/bookmarks_31_05_2026.html` 是用户提供的示例书签文件，当前未跟踪；不得提交。
- 示例书签文件约 3392 行，格式为 `<!DOCTYPE NETSCAPE-Bookmark-file-1>`。
- 示例文件包含浏览器书签常见字段：
  - 文件夹：`<DT><H3 ADD_DATE="..." LAST_MODIFIED="..." PERSONAL_TOOLBAR_FOLDER="true">...`
  - 书签：`<DT><A HREF="..." ADD_DATE="..." ICON="...">title</A>`
  - 层级：`<DL><p>` / `</DL><p>`
- 示例文件中包含 base64 `ICON` 字段、中文/日文标题，以及疑似 mojibake 乱码标题。
- 新 skill 必须内置必要的书签分类方法论；职责聚焦书签格式、链接检测、报告、整理计划和可审核操作，不依赖其他 skill 的路径或文档。
- `.trellis/spec/infra/agent-skill-dev.md` 规定：
  - 复杂 Python 脚本型 skill 若需要第三方依赖，应使用独立 uv 项目，提交 `pyproject.toml` 与 `uv.lock`。
  - 安装态入口应通过 `uv run python -m <package>.cli [args]`，不得要求手工 `pip install` 或依赖本机 venv。
  - Python 代码应有类型标注；公共函数和 CLI 入口应说明核心功能、入参、返回值和退出码语义。

## Requirements

- 新 skill 目录建议为 `ai/skills/dev/browser-bookmark-organizer/`。
- 使用 Python 实现，依赖型脚本采用 uv 项目结构。
- 书签解析必须支持 Netscape Bookmark HTML。
- 首版必须支持读取本地 HTML 文件、输出结构化报告，并默认启动本地临时 WebUI 作为全程状态入口。
- 首版应引入 run workspace 概念，把用户数据、报告、选择记录和操作日志写到用户指定目录，避免写入 skill 目录。
- 首版应能统计：
  - 文件夹数量、书签数量、最大目录深度。
  - URL scheme / domain 分布。
  - 重复 URL 或规范化后重复 URL。
  - 空文件夹。
  - 疑似乱码或空标题。
- 首版支持链接检测，但必须由用户显式传入 `--check-links` 才启用，使用 `httpx`：
  - 支持 timeout。
  - 支持是否跟随重定向。
  - 输出 HTTP 状态、最终 URL、错误类别和耗时。
  - 默认应限制并发和请求速率，避免对网站造成过大压力。
  - 必须识别局域网、Tailscale 和公司内网候选链接；默认不检测这些上下文依赖链接，不把当前网络不可达误判为死链。
  - 需要提供显式参数允许用户在对应网络环境中检测私网类链接，并记录检测时的 network context。
- 默认不修改原始书签 HTML，不生成可导入的新书签文件，除非用户明确批准后续范围。
- 输出优先为本地 WebUI URL，同时保留 HTML 报告、Markdown 报告和 JSON 数据作为副产物，便于人审、保存和后续自动处理。
- 提供本地临时 WebUI 服务，绑定 `127.0.0.1`，默认后台启动并在 1 小时后自动关闭，CLI 必须输出服务 URL、PID 和日志路径，让用户全程查看当前书签状态、阶段进度、操作日志、审核结果并提交选择，选择记录写入 workspace 的 `decisions.json`。
- 服务日志使用 Python `logging` 与模块级 `logger = logging.getLogger(__name__)`；stdout 只输出 URL、PID、路径和错误摘要等即时入口信息。
- 时间戳统一通过包内封装生成，默认使用系统本地时区，避免固定 UTC 或散落时区逻辑。
- WebUI 应展示由原始 snapshot + 已批准 operations replay 得到的当前状态，而不只是最后的静态报告。
- CLI 应支持子命令式流程，至少包含 `analyze`、`tree`、`status`、`apply-ops`、`export`、`review` 和兼容旧版直接分析入口。
- 必须明确 `ai/skills/bookmarks_31_05_2026.html` 不提交；如需测试 fixture，应创建脱敏/极小样例。

## Acceptance Criteria

- [ ] `prd.md` 明确 MVP 范围、脚本结构、依赖和不提交示例文件的约束。
- [ ] 若进入实现，存在 `ai/skills/dev/browser-bookmark-organizer/SKILL.md`。
- [ ] 若进入实现，Python 项目包含 `pyproject.toml`、`uv.lock`、`src/`、`tests/`。
- [ ] CLI 能解析 Netscape Bookmark HTML 并输出报告。
- [ ] CLI 能创建 workspace，并写入 `analysis.json`、`bookmark-report.md`、`bookmark-report.html`。
- [ ] CLI 能在不联网模式下完成统计、重复项、空目录、乱码标题等检查。
- [ ] 链接检测如果进入 MVP，使用 HTTPX 并覆盖 timeout、redirect、错误分类和并发限制。
- [ ] `analyze --workspace` 默认后台启动本地 WebUI，输出 `Review UI: http://127.0.0.1:<port>`、PID 和日志路径，并默认 1 小时自动关闭。
- [ ] 本地 WebUI 服务能读取 workspace 数据、展示当前状态并保存用户提交的 `decisions.json`。
- [ ] CLI 能基于 `snapshot.json` + `operations.jsonl` replay 当前状态、输出目录树、追加操作并导出新的书签 HTML。
- [ ] 原始 `ai/skills/bookmarks_31_05_2026.html` 不被提交。
- [ ] 核心解析和链接检测逻辑有测试覆盖。

## Out of Scope

- 首版不自动改写用户原始书签文件。
- 首版不直接导入浏览器 profile 数据库。
- 首版不处理浏览器同步账号或云端书签 API。
- 首版不做全文网页内容抓取、截图、网页摘要或 AI 自动打标签。
- 首版本地 WebUI 服务只提供状态查看、审核与选择记录，不直接执行删除或批量重写原文件。

## Resolved Questions

- 链接检测进入 MVP，但不是默认行为；默认离线统计，传入 `--check-links` 后才联网检测。
- 交互审核使用本地临时服务更合适；用户选择记录写入 workspace，不写入 skill 目录。
- 报告需要精美 HTML 样式，采用安静、信息密集、可扫描的 dashboard/report 视觉风格。
- 局域网、Tailscale 和公司内网链接是上下文依赖链接，默认进入“需要对应网络环境复测”，不是死链候选。
- WebUI 应作为整理全过程的实时状态面板，后续每次 CLI 应用操作后都能刷新看到当前目录树、待处理链接和操作日志变化。
- `analyze` 默认后台启动 WebUI；静态 `bookmark-report.html` 只是副产物。需要批处理时可显式使用 `--no-review`，需要调试服务时使用 `--foreground`。
- 最终导出由原始解析 snapshot + 已批准 operations replay 生成，不直接修改原始书签 HTML。
