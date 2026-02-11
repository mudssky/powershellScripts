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
