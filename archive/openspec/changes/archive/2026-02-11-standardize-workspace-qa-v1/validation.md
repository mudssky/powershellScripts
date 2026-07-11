## Validation Context

- 执行日期：2026-02-11
- 执行环境：本地 Linux 开发容器（当前沙箱）
- 变更名称：`standardize-workspace-qa-v1`
- 说明：本次记录用于验证 V2 Turbo 引入后的命令映射、缓存信号与失败定位可读性；结果可作为 CI 对照基线。

## Validation Method

### Scenario Matrix

- `cold(all)`：首次执行 `qa:all` 与 `turbo:qa:all`
- `warm(all)`：再次执行 `qa:all` 与 `turbo:qa:all`
- `changed(PR)`：执行 `qa` 与 `turbo:qa`

### Commands

- `pnpm qa:all`
- `pnpm turbo:qa:all`
- `pnpm qa`
- `pnpm turbo:qa`
- `pnpm -C scripts/node run qa`
- `pnpm -C projects/clis/json-diff-tool run qa`
- `pnpm -C projects/clis/pwshfmt-rs run qa`

## Validation Results

### Runtime Comparison (V1 vs V2)

| 场景 | 命令 | 退出码 | 耗时(ms) | 缓存命中摘要 |
|---|---|---:|---:|---|
| cold(all) V1 | `pnpm qa:all` | 1 | 8760.07 | N/A |
| cold(all) V2 | `pnpm turbo:qa:all` | 1 | 14651.73 | `1/3`（33.33%） |
| warm(all) V1 | `pnpm qa:all` | 1 | 8691.17 | N/A |
| warm(all) V2 | `pnpm turbo:qa:all` | 1 | 12530.35 | `1/3`（33.33%） |
| changed(PR) V1 | `pnpm qa` | 0 | 4172.33 | N/A |
| changed(PR) V2 | `pnpm turbo:qa` | 0 | 4275.89 | N/A |

### Longest Package (单包 QA 耗时)

| 包名 | 命令 | 退出码 | 耗时(ms) |
|---|---|---:|---:|
| `node-script` | `pnpm -C scripts/node run qa` | 1 | 3744.65 |
| `json-diff-tool` | `pnpm -C projects/clis/json-diff-tool run qa` | 0 | 8746.02 |
| `pwshfmt-rs-wrapper` | `pnpm -C projects/clis/pwshfmt-rs run qa` | 0 | 2588.71 |

结论：当前样本中最长耗时包为 `json-diff-tool`。

### Failure Readability

- V1（`pnpm qa:all`）失败时以脚本步骤报错为主，缺少统一任务摘要。
- V2（`pnpm turbo:qa:all`）可直接定位失败任务 `node-script#qa`，并输出 `Tasks/Cached/Time/Failed` 摘要。
- 在“失败定位可读性”维度，V2 输出结构更稳定，便于 CI 首屏排障。

## Notes

- `qa:all` 路径在当前沙箱下会触发 `node-script` 的 `tsx` IPC 管道权限错误（`listen EPERM`），导致 all 场景返回非零；该问题属于现有测试运行环境限制，不是本次 Turbo 接入引入的新问题。
- CI 已补充完整历史前置（`actions/checkout` 设置 `fetch-depth: 0`），用于保证 Turbo affected 计算稳定。

## V2.1 Optimization Notes

- `turbo:qa*` 已切换为细粒度链路：`turbo run typecheck:fast check test:fast`（不再依赖单任务 `turbo run qa`）。
- `turbo.json` 已增加任务依赖与输入边界，`check` 依赖 `typecheck:fast`，`test:fast` 依赖 `check`，并排除文档类目录输入。
- 本地 warm 对比样本显示缓存命中提升：`Cached: 9 cached, 9 total`（采样时间：2026-02-11）。
- 远程缓存提供可选开关：`TURBO_REMOTE_CACHE=1` 时启用；若缺少 `TURBO_TOKEN` 或 `TURBO_TEAM`，脚本会显式报错并给出提示。
- `node-script` 在容器中的 `tsx` IPC `EPERM` 问题已通过调整 `tests/cli.test.ts` 的运行策略规避（改为输出落盘读取，避免 pipe 捕获不稳定）。
- CI 新增 Turbo 基准采样作业，输出 `artifacts/qa-benchmarks`（包含 `latest.json`、时间戳样本与 `summary.md`），覆盖 `cold(all)`、`warm(all)`、`changed(PR)`。

### Latest Benchmark Snapshot (2026-02-11)

| 场景 | 命令 | 退出码 | 耗时(ms) | 缓存命中摘要 |
|---|---|---:|---:|---|
| cold(all) V1 | `pnpm qa:all` | 0 | 27901.63 | N/A |
| cold(all) V2 | `pnpm turbo:qa:all` | 0 | 31797.53 | `9 cached, 9 total` |
| warm(all) V1 | `pnpm qa:all` | 0 | 30461.06 | N/A |
| warm(all) V2 | `pnpm turbo:qa:all` | 0 | 31518.36 | `9 cached, 9 total` |
| changed(PR) V1 | `pnpm qa` | 0 | 16457.77 | N/A |
| changed(PR) V2 | `pnpm turbo:qa` | 0 | 1977.00 | `9 cached, 9 total` |
