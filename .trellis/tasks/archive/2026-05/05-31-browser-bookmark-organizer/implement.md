# 实现计划

## Steps

- [x] 启动 Trellis 任务并读取 `agent-skill-dev` 规范。
- [x] 决定链接检测进入 MVP，但作为显式 `--check-links` 可选能力。
- [x] 创建 skill 文档与 reference。
- [x] 创建 uv Python 项目结构。
- [x] 实现 Netscape Bookmark HTML 解析。
- [x] 实现离线分析：统计、重复、空目录、疑似乱码/空标题。
- [x] 实现 HTTPX 链接检测：timeout、redirect、错误分类、并发限制。
- [x] 实现 Markdown/JSON 报告输出。
- [x] 补充脱敏 fixture 与核心测试。
- [x] 运行验证命令并修复问题。
- [x] 引入 workspace、HTML 报告和本地 review 服务设计。
- [x] 重构 CLI 为 `analyze` / `review` 子命令并保留旧入口兼容。
- [x] 实现 review 页面保存 `decisions.json`。
- [x] 补充 workspace、HTML 报告和 review 服务测试。
- [x] 识别局域网、Tailscale、公司内网等上下文依赖链接，默认不误判为死链。
- [x] 实现 snapshot + operations replay 当前状态、目录树输出、operation 追加和新书签 HTML 导出。

## Notes

- 用户原始示例 `ai/skills/bookmarks_31_05_2026.html` 只作为本地理解材料，不纳入 fixture，不提交。
- 如果实际样例验证需要输出报告，输出到临时目录或未跟踪报告路径。
