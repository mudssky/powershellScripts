## Why

Windows 上 `loadModule` 阶段耗时 225ms，占 profile 总加载时间 30%。分析发现 6 个同步加载的核心模块中有 2 个在启动路径中实际未被调用（`test.psm1` 在 Phase 4 已被 `Get-Command` 替代，`env.psm1` 仅 Linux 使用 `Sync-PathFromBash`）。此外代理缓存 TTL 仅 5 分钟，冷启动或频繁开终端时 TCP 探测耗时 ~117ms。

## What Changes

- 从核心同步加载列表移除 `test.psm1`，延迟到 OnIdle 全量加载
- `env.psm1` 改为条件加载：仅 Linux 同步加载，Windows/macOS 跳过
- 代理自动检测缓存 TTL 从 5 分钟延长到 30 分钟
- `Debug-ProfilePerformance.ps1` 同步更新上述变更

## Capabilities

### New Capabilities

（无新增能力）

### Modified Capabilities

- `psutils-deferred-loading`: `test.psm1` 从同步路径移至延迟加载；`env.psm1` 按平台条件化加载
- `profile-perf-diagnostics`: 诊断脚本中核心模块加载逻辑同步更新

## Impact

- `profile/core/loadModule.ps1` — 核心模块列表变更
- `profile/features/environment.ps1` — 代理缓存 TTL 变更
- `profile/Debug-ProfilePerformance.ps1` — 同步模块加载逻辑 + 缓存 TTL
- `profile/README.md` — 性能基线数据更新
- 预计 Windows loadModule 从 ~225ms 降到 ~150ms，代理冷启动省 ~100ms
