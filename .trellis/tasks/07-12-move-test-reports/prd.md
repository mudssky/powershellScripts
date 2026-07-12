# 迁移测试报告输出目录

## Goal

把本地与 CI 生成的测试报告统一收敛到 `tests/reports/`，避免 `coverage.xml`、`testResults.xml` 和 `vitest-report.xml` 出现在仓库根目录，并消除 Pester 输出路径随当前工作目录漂移的问题。

## Background

- `PesterConfiguration.ps1` 当前把 `TestResult.OutputPath` 设为相对路径 `testResults.xml`，因此从根目录运行时写入根目录，从 `psutils/` 等目录运行时会写入对应子目录。
- Pester coverage 使用 `CoverageGutters`，当前未显式配置 `CodeCoverage.OutputPath`，本地已有根目录 `coverage.xml`。
- GitHub Actions 的 Pester reporter 固定读取根 `testResults.xml`，Vitest 命令固定写根 `vitest-report.xml`。
- Linux Docker Pester 结果写入 named volume `/workspace-output/testResults-linux.xml`，不会占用仓库根目录，本任务保持该隔离策略。
- Context7 的当前 Pester 文档确认 `CodeCoverage.OutputPath` 与 `TestResult.OutputPath` 均支持包含目录和 XML 文件名的显式路径。

## Requirements

- R1：新增受 Git 跟踪的 `tests/reports/` 目录占位文件，报告 XML 本身继续忽略。
- R2：Pester 默认测试结果固定写入 `<repo>/tests/reports/testResults.xml`，不受调用方当前目录影响。
- R3：Pester coverage 固定写入 `<repo>/tests/reports/coverage.xml`。
- R4：保留 `PESTER_RESULT_PATH` 覆盖能力；显式覆盖路径仍由调用方负责选择。
- R5：`PesterConfiguration.ps1` 在返回配置前确保默认报告目录存在。
- R6：GitHub Actions Pester reporter 读取 `tests/reports/testResults.xml`。
- R7：Vitest CI 写入并发布 `tests/reports/vitest-report.xml`。
- R8：更新 `.gitignore` 和 `docs/local-cross-platform-testing.md`，反映新路径。
- R9：Linux Docker 的 `testResults-linux.xml` 继续写入 `pester-results` named volume，不迁入工作区。
- R10：清理当前根目录和 `psutils/` 下已生成的同类 XML；现有根目录三个报告移动到 `tests/reports/`，重复的 `psutils/testResults.xml` 删除或移出工作区。
- R11：不纳入并行 psutils Trellis 任务的改动。
- R12：修复 `test:pwsh:full` 在 zsh/Unix shell 下提前展开 `$env:` 的既有问题，统一复用 `Invoke-PesterMode.ps1 -Mode full -Coverage On`，保证 coverage 门禁可执行。

## Acceptance Criteria

- [x] 从仓库根目录和子目录加载 Pester 配置时，默认报告路径均解析到 `tests/reports/`。
- [x] coverage 与 NUnit 测试结果能成功写入 `tests/reports/`。
- [x] Vitest CI 和 Pester CI reporter 使用新路径。
- [x] 仓库根目录及 `psutils/` 不再存在目标 XML 报告。
- [x] `tests/reports/.gitkeep` 被跟踪，生成的 XML 被忽略。
- [x] `pnpm qa`、`pnpm test:pwsh:all` 和 `pnpm test:pwsh:coverage` 通过。

## Out Of Scope

- 不改变 Linux Docker named volume 的报告位置。
- 不迁移 benchmark JSON、Playwright 报告或其他测试工具产物。
