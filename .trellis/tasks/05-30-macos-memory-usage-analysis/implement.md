# macOS 内存诊断脚本优化实施计划

## Checklist

- [x] 阅读 `trellis-before-dev` 指向的 PowerShell 脚本规范。
- [x] 为 macOS `vm_stat` 解析补充页面级字段和压缩内存字段。
- [x] 增加 `memory_pressure` 与 `vm pressure level` 采集，并将结果并入 `System`。
- [x] 将 macOS Top 进程采集改为 `ps -ww`，保留通用解析函数兼容性。
- [x] 增加 Docker Desktop VM 内存上限解析，作为 Docker snapshot 的 macOS 扩展字段。
- [x] 增加 macOS 专属 recommendations：swap/压缩压力、Docker VM 上限高于实际容器使用、macOS 自动管理说明。
- [x] 增加 Pester 测试覆盖新增解析逻辑和建议规则。
- [x] 运行现有脚本 snapshot，确认 macOS 输出更可读。
- [x] 运行 `pnpm qa`。
- [x] 运行 `pnpm test:pwsh:all`；Docker 不可用时降级到 `pnpm test:pwsh:full` 并记录边界。
- [x] 修复 `pwshfmt-rs --strict-fallback` 在 `core/docker.ps1` 与 `platforms/macos.ps1` 上通过适配层递归调用自身的问题。

## Validation Notes

- `pwsh -NoProfile -Command '$env:PWSH_TEST_MODE="debug"; $env:PWSH_TEST_PATH="./tests/MemoryDiagnostics.Tests.ps1"; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c'`：通过，16 个测试全部成功。
- `pwsh -NoProfile -File scripts/pwsh/devops/memory-diagnostics/main.ps1 snapshot -Top 5 -Depth full`：通过，macOS 输出包含完整进程路径、`memoryPressureFreePercent`、`compressorGB`、Docker Desktop VM 上限和 3 条 macOS 建议。
- `pnpm qa`：通过。
- `pnpm test:pwsh:all`：通过，host 581 passed / linux 583 passed。
- `pwshfmt-rs` strict fallback 根因：Rust fallback runner 调用 `Format-PowerShellCode.ps1 -Strict`，而该 PowerShell 适配层又把 `-Strict` 翻译为 `pwshfmt-rs write --strict-fallback`，导致 `core/docker.ps1` 与 `platforms/macos.ps1` 的 unsafe token 文件反复回调自身。
- 修复后验证：
  - `cargo run --manifest-path ./projects/clis/pwshfmt-rs/Cargo.toml -- check --path scripts/pwsh/devops/memory-diagnostics/core/docker.ps1 --strict-fallback`：通过，`fallback=true`，未再递归。
  - `cargo run --manifest-path ./projects/clis/pwshfmt-rs/Cargo.toml -- check --path scripts/pwsh/devops/memory-diagnostics/platforms/macos.ps1 --strict-fallback`：通过，`fallback=true`，未再递归。
  - `pwsh -NoProfile -File ./scripts/pwsh/devops/Format-PowerShellCode.ps1 -Path scripts/pwsh/devops/memory-diagnostics -Recurse -Strict`：通过，10 个文件 unchanged，其中 2 个文件走 fallback。
  - `pnpm --filter pwshfmt-rs qa`：通过。
  - `pnpm qa`：通过。
  - `pnpm test:pwsh:all`：通过，host 581 passed / linux 583 passed。
  - `git diff --check`：通过。

## Risky Files

- `scripts/pwsh/devops/memory-diagnostics/platforms/macos.ps1`
- `scripts/pwsh/devops/memory-diagnostics/core/docker.ps1`
- `scripts/pwsh/devops/memory-diagnostics/core/thresholds.ps1`
- `tests/MemoryDiagnostics.Tests.ps1`

## Rollback Points

- macOS 采集增强应能单独回滚，不影响 Windows/Linux。
- Docker VM 字段解析失败时必须降级为空字段或 warning，不应让整个报告失败。
