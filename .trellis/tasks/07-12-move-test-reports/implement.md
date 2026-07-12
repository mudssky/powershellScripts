# 实施计划

- [x] 读取 `trellis-before-dev` 及 pwsh/infra 相关规范。
- [x] 新增 `tests/reports/.gitkeep`，更新 `.gitignore`。
- [x] 修改 `PesterConfiguration.ps1`，创建稳定报告目录并配置测试结果、coverage 输出路径。
- [x] 更新 `.github/workflows/test.yml` 的 Pester 与 Vitest 报告路径。
- [x] 更新 `docs/local-cross-platform-testing.md`。
- [x] 移动现有 ignored XML，确认根目录和 `psutils/` 不再残留报告。
- [x] 新增 Pester 配置路径回归验证，根目录与子目录路径一致，覆盖变量仍有效。
- [x] 修复并验证 `test:pwsh:full` / `test:pwsh:coverage` 的跨 shell 执行入口。
- [x] 运行 `pnpm qa`、`pnpm test:pwsh:all` 和 `pnpm test:pwsh:coverage`。
- [x] 检查 Git diff、忽略规则和生成文件位置。
- [ ] 只提交本任务相关文件，归档 Trellis 任务并记录会话。

## 验证备注

- Vitest JUnit 命令成功生成 `tests/reports/vitest-report.xml`。
- 全量 Vitest 存在 37 个与本任务无关的既有失败，包括 macOS Bash 3 兼容、json-diff-tool 缺少 workspace 依赖和 `/private/var` 路径规范化差异；本任务未扩展修复。
