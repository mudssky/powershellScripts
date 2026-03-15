---
module: System
date: 2026-03-15
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "`pnpm test:pwsh:all` 剩余少数共享热点仍然主导墙钟时间"
  - "`help.Tests.ps1` 中的性能对比型测试混入默认 full 门禁"
  - "默认通过日志仍混入 `WhatIf` 与预期 fallback warning，稀释失败定位"
root_cause: mixed_test_responsibilities
resolution_type: code_fix
severity: medium
tags: [powershell, pester, benchmark, performance, console-output, pre-commit]
---

# Troubleshooting: 将 help 性能比较迁移到 benchmark，并收口 full 日志噪音

## Problem

在上一轮跨平台稳定性修复之后，`pnpm test:pwsh:all` 仍有两类明显剩余成本：

1. `psutils/tests/help.Tests.ps1`、`tests/Invoke-Benchmark.Tests.ps1`、`psutils/tests/cache.Tests.ps1` 这类共享热点继续拉高 host / linux 的整体墙钟时间。
2. 默认 full 通过日志里仍混入 `WhatIf` 主机提示与预期 fallback warning，真正需要看的测试文件进度与失败信息被稀释。

其中最不适合继续留在 full 门禁里的，是 `Test-HelpSearchPerformance`。它本质上是“自定义解析 vs Get-Help”的性能比较，更像 benchmark / 诊断任务，而不是功能正确性断言。

## Environment

- Module: System
- Affected Component:
  - `psutils/modules/help.psm1`
  - `psutils/tests/help.Tests.ps1`
  - `tests/benchmarks/HelpSearch.Benchmark.ps1`
  - `tests/Invoke-Benchmark.Tests.ps1`
  - `psutils/tests/cache.Tests.ps1`
  - `tests/Sync-PathFromBash.Tests.ps1`
  - `psutils/tests/env.Tests.ps1`
  - `psutils/tests/web.Tests.ps1`
  - `README.md`
  - `docs/local-cross-platform-testing.md`
- Platform: Windows host + Linux Docker container
- Date: 2026-03-15

## Symptoms

- 基线 `test.log` 中：
  - host `Tests completed in 39.05s`
  - linux `Tests completed in 40.4s`
  - `help.Tests.ps1` 在 linux 达到 `18.1s`
  - 日志包含 `32` 行 `What if:` 与 `3` 条 `WARNING:`
- 默认 full 中的 `WhatIf` 提示不能靠 `6>$null` 或 preference 变量静音。
- `Test-HelpSearchPerformance` 在 full 下运行会把诊断型成本直接计入提交门禁。

## Solution

这轮修复做了三件事：

### 1. 把 help 性能比较从 full 门禁迁移到 benchmark

- `psutils/tests/help.Tests.ps1` 删除 `Test-HelpSearchPerformance` 的默认 full 断言。
- `psutils/modules/help.psm1` 中的 `Test-HelpSearchPerformance` 新增 `-Quiet`，让 benchmark 可拿到干净的结构化结果。
- 新增 `tests/benchmarks/HelpSearch.Benchmark.ps1`，通过 `pnpm benchmark -- help-search` 提供可 discover 的性能对比入口。
- `tests/Invoke-Benchmark.Tests.ps1` 增加 `help-search` 的显式 benchmark smoke，确保新 benchmark 不会“迁走后无人验证”。

### 2. 收口默认 full 日志里的残余噪音

- `tests/Sync-PathFromBash.Tests.ps1`
  - 改为在子进程里验证 `-WhatIf` 主机提示，父 Pester 进程只断言语义与捕获结果，避免默认 full 日志继续刷出 `WhatIf`。
- `psutils/tests/env.Tests.ps1`
  - 对已知的 Linux/macOS `Path` 大小写 warning 加上 `-WarningAction SilentlyContinue`。
- `psutils/tests/web.Tests.ps1`
  - 将 `Save-Icon` 预期 fallback warning 收口到测试边界。
- `psutils/tests/cache.Tests.ps1`
  - 对 `Invoke-WithCache -WhatIf` 使用子进程验证，避免默认日志残留主机提示。

### 3. 用回拨文件时间戳替代真实等待

- `psutils/tests/cache.Tests.ps1`
  - 过期相关测试不再 `Start-Sleep`，改为直接回拨缓存文件 `LastWriteTime`，保持语义不变但减少等待。

### Commands run

```bash
pnpm benchmark -- help-search -SearchTerm Benchmark -ModulePath artifacts/help-search-fixture -OutputPath artifacts/help-search-fixture2.json
pnpm qa
pnpm test:pwsh:all
```

## Verified result

### Wall-clock improvements

- 基线：
  - host `39.05s`
  - linux `40.4s`
- 修复后：
  - host `34.65s`
  - linux `32.75s`

### Hotspot changes

- `psutils/tests/help.Tests.ps1`
  - host `5.04s` → `3.51s`
  - linux `18.1s` → `10.86s`
- `psutils/tests/cache.Tests.ps1`
  - host `5.48s` → `5.23s`
  - linux `5.11s` → `4.25s`

### Output quality

- `pnpm test:pwsh:all` 默认通过日志中不再出现批量 `WhatIf` / 预期 fallback warning。
- 文件级进度、失败详情与最终汇总仍然保留。

### Quality gates

- `pnpm qa` 通过
- `pnpm test:pwsh:all` 通过
- `pnpm benchmark -- help-search` 可运行

## Why This Works

这次收口的核心不是“再静音一点输出”，而是把测试职责重新放回正确边界：

- **性能比较走 benchmark**，因此 full 门禁只保留功能正确性与跨平台断言。
- **PowerShell 主机提示在子进程中验证**，因此 `WhatIf` 语义仍被测试，但不会继续污染默认门禁日志。
- **真实等待改成时间戳回拨**，因此缓存过期语义仍然基于真实文件元数据，而不是硬删断言或依赖睡眠。

## Prevention

- 诊断型性能比较不要直接混入默认 `test:pwsh:all` / full 门禁，优先提供独立 benchmark 入口。
- 只要是 PowerShell `WhatIf` 主机提示，默认假设它不会被常规重定向静音；测试应优先用子进程隔离。
- 对需要验证“过期”的缓存 / 文件系统测试，优先操纵时间戳或输入状态，不要默认使用 `Start-Sleep`。
- benchmark 从 full 迁出后，必须保留最小 CLI smoke，避免 discoverability 回归。

## Related Issues

- See also: [pwsh-cross-platform-test-gate-performance-stability-system-20260315.md](./pwsh-cross-platform-test-gate-performance-stability-system-20260315.md)
- See also: [pwsh-cross-platform-test-workflow-stability-system-20260314.md](./pwsh-cross-platform-test-workflow-stability-system-20260314.md)
- See also: [benchmark-interactive-selection-psutils-20260314.md](../developer-experience/benchmark-interactive-selection-psutils-20260314.md)
