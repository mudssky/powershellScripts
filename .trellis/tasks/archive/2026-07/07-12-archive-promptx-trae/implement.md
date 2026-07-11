# PromptX 与 Trae 归档实施计划

## 1. 启动

- [x] 用户审阅 PRD 和设计并批准实施。
- [x] 启动 Trellis task，加载 `trellis-before-dev` 和归档规范。
- [x] 记录 Git 状态并运行归档索引 `check`。

## 2. 执行归档

- [x] 使用已审阅参数执行 `.promptx` 归档。
- [x] 使用已审阅参数执行 `.trae` 归档。
- [x] 使用已审阅参数执行 `openspec` 归档。
- [x] 确认三个源目录消失、镜像目标存在、JSON 增至 11 条。
- [x] 确认 `.vercel` 没有跟踪文件且未产生新记录。

## 3. 修复活动引用

- [x] 从 `README.md` 目录树移除 `.trae`。
- [x] 更新 `.betterleaksignore` 的 3 条归档路径。
- [x] 更新 fnOS mount manager 计划中的 6 处 Trae 文档引用。
- [x] 删除 `turbo.json` 中 3 条 OpenSpec 专用排除。
- [x] 删除应用安装清单中的 npm/bun OpenSpec 项。
- [x] 将 `docs/plans/**` 中明确的 `openspec/specs/**` 路径迁到归档镜像。
- [x] 搜索剩余引用并按设计分类，保持通用支持和历史记录不变。

## 4. 验证

- [x] 运行 `project-archive check`：11 条索引通过。
- [x] 运行 `pnpm qa`：120 通过、0 失败、6 未运行。
- [x] 运行 `pnpm test:pwsh:all`：Host 759 通过、Linux 756 通过，均 0 失败。
- [x] 运行 `git diff --check` 和 rename summary：278 个 100% rename。
- [x] 提交后使用 `git log --follow` 抽查 PromptX、Trae 与 OpenSpec 新路径，均可追溯迁移前历史。
- [x] 确认 `.betterleaksignore` 例外精确指向被移动文档；本机缺少 `betterleaks` 可执行文件，未能执行扫描命令。

## 5. 收尾

- [x] 更新验收与验证结果。
- [x] 提交 `bca88cb chore(repo): 归档 PromptX、Trae 与 OpenSpec`。
- [x] 归档 Trellis task 并记录 session。
