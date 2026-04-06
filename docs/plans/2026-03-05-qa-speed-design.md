# QA 提速与降噪设计（Windows）

## 背景

- 现状 `pnpm qa` 在 Windows 上会触发大量慢测与噪音输出，耗时远超本地快速反馈目标。
- `test:fast` 存在环境变量转义问题，导致模式未生效，实际执行接近全量。

## 目标

- 本地 `pnpm qa` 目标耗时尽量控制在 20 秒以内。
- 输出保留“每个测试文件耗时 + 错误/失败 + 汇总”，减少无关噪音。
- 慢测从 `qa` 中剥离，保留在 `test:fast`/`test:full` 或 CI 场景执行。

## 设计

### 1) 命令分层

- 新增 `test:qa`（`PWSH_TEST_MODE=qa`）。
- `qa:pwsh` 从 `test:fast` 切换为 `test:qa`。
- 修复 `test:fast/full/serial/debug` 的 PowerShell 环境变量转义。

### 2) 测试集策略

- `qa` 采用“固定 smoke + changed-aware”策略：
  - 固定 smoke：一组低耗时基础测试，始终执行。
  - changed-aware：根据改动文件追加相关测试。
- 显式排除已知慢/高噪音测试文件，避免本地质量门被拖慢。

### 3) 调度实现

- 在 `scripts/qa.mjs` 增加：
  - 变更文件收集（工作区、暂存区、未跟踪 + 与基线对比）。
  - 路径映射规则（`psutils/modules/<name>.psm1 -> psutils/tests/<name>.Tests.ps1`）。
  - `PWSH_TEST_PATH` 注入 `qa:pwsh`，由 Pester 只执行目标子集。

### 4) Pester 模式

- `PesterConfiguration.ps1` 增加 `qa` 模式：
  - 默认 `Run.Path` 使用 smoke 集合；
  - 支持 `PWSH_TEST_PATH` 覆盖；
  - 关闭 CodeCoverage；
  - 保持 `Output.Verbosity='Normal'`。

## 风险与权衡

- 风险：`qa` 覆盖面降低可能漏检非 smoke 问题。
- 缓解：保留 `test:fast`/`test:full` 作为更全面验证入口，CI 中继续执行更重测试。

## 验证标准

- `pnpm qa` 在常见变更场景下显著低于历史耗时。
- `pnpm qa` 输出仍包含文件级耗时与失败摘要。
- `pnpm test:fast` 环境变量生效，不再出现 `\$env:` 解释错误。
