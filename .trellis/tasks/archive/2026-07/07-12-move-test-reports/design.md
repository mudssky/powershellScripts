# 技术设计

## 路径契约

`PesterConfiguration.ps1` 位于仓库根目录，因此以 `$PSScriptRoot` 作为稳定仓库根：

```powershell
$reportDirectory = Join-Path $PSScriptRoot 'tests/reports'
$defaultTestResultPath = Join-Path $reportDirectory 'testResults.xml'
$defaultCoveragePath = Join-Path $reportDirectory 'coverage.xml'
```

配置加载时用 `New-Item -ItemType Directory -Force` 确保目录存在。`PESTER_RESULT_PATH` 非空时继续覆盖默认测试结果路径；coverage 本轮只提供固定默认路径，不增加新的环境变量。

## CI

- Pester：测试命令无需变化，`dorny/test-reporter` 的 `path` 改为 `tests/reports/testResults.xml`。
- Vitest：`--outputFile.junit` 和 reporter `path` 都改为 `tests/reports/vitest-report.xml`。
- checkout 后 `tests/reports/.gitkeep` 确保父目录存在；Pester 配置仍自行创建目录，避免依赖占位文件。

## 忽略与现有文件

- 根 `.gitignore` 使用 `/tests/reports/*.xml`，保留 `.gitkeep`。
- 当前根目录三个 XML 移入 `tests/reports/`，它们仍为忽略的生成物，不进入提交。
- `psutils/testResults.xml` 是相对路径漂移产生的重复报告，清理出工作区。

## 验证

- 分别从仓库根和 `psutils/` 加载配置，断言默认路径相同。
- 运行 `pnpm qa` 与 `pnpm test:pwsh:all`，确认 host 报告落在新目录且 Linux named volume 路径不变。
- 检查 CI YAML、文档和 Git ignore 不再引用根目录报告路径。

## 回滚

恢复旧相对路径、CI reporter 路径和 ignore 规则，删除 `.gitkeep`；生成的 XML 可直接删除，无需纳入 Git 回滚。
