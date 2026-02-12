## Context

Profile 核心模块加载（`core/loadModule.ps1`）当前同步加载 6 个 psutils 子模块：`os → cache → test → env → proxy → wrapper`，每个 `Import-Module` 在 Windows 上耗时 ~35-40ms。分析发现 `test.psm1` 和 `env.psm1` 在 Phase 4（`Initialize-Environment`）中不再被直接调用：

- `test.psm1`：`Test-EXEProgram` 已被 `Get-Command` 批量检测完全替代，唯一调用方 `wrapper.ps1` 在 OnIdle 加载
- `env.psm1`：`Sync-PathFromBash` 仅 `$IsLinux` 条件下调用，`Add-EnvPath` 在 profile 中完全未使用

代理缓存 TTL 5 分钟在频繁开终端场景下过短，每 5 分钟需重新 TCP 探测一次代理端口（~117ms）。

## Goals / Non-Goals

**Goals:**

- 减少 Windows loadModule 阶段 ~70-80ms（从 6 模块降到 4 模块）
- 减少代理检测冷启动频率（TTL 从 5 分钟延长到 30 分钟）
- 保持 Linux 平台功能完整（`Sync-PathFromBash` 仍在同步路径可用）
- 保持向后兼容（所有函数最终通过 OnIdle 可用）

**Non-Goals:**

- 不优化 `encoding.ps1` 的 JIT 开销（66ms，属于 .NET 冷启动固有成本）
- 不优化 `Get-Command` 的 NTFS 遍历耗时（72ms，已通过 sccache 安装优化过）
- 不移动 `proxy` 到 OnIdle（代理设置需要在工具初始化前生效）

## Decisions

### Decision 1: test.psm1 完全移出同步路径

将 `test.psm1` 从 `$coreModules` 列表移除。理由：
- Phase 4 已用 `Get-Command -Name $toolNames -CommandType Application` 替代 `Test-EXEProgram`
- `wrapper.ps1` 中的 `Test-EXEProgram` 调用在 OnIdle 路径，OnIdle 会全量加载 psutils 覆盖
- 替代方案「保留加载但标记为可选」增加复杂度无收益

### Decision 2: env.psm1 按平台条件加载

- Linux/macOS: 保留在同步路径（`Sync-PathFromBash` 需要）
- Windows: 移出同步路径

不采用「全平台移除 + 懒加载」，因为 Linux 上 `Sync-PathFromBash` 在 Phase 4 早期被调用（4.02），懒加载会增加复杂度且首次调用有延迟。

### Decision 3: 代理缓存 TTL 从 5 分钟延长到 30 分钟

理由：
- 代理状态在 30 分钟内极少变化
- 5 分钟 TTL 在频繁开终端时几乎每次都过期
- 用户主动切换代理时通常会运行 `Set-Proxy` 手动覆盖

## Risks / Trade-offs

- [Risk] `test.psm1` 移出后，同步路径中如果有代码引用 `Test-EXEProgram` 会在 PSModulePath 自动导入时全量加载 psutils → 现有 Pester 防护栏测试 SHALL 检测到此类回归
- [Risk] 代理 TTL 30 分钟内代理状态变更（如 VPN 切换）不会自动反映 → 用户可通过 `Set-Proxy -Command auto` 手动刷新
- [Risk] `env.psm1` 按平台条件化后，`loadModule.ps1` 逻辑略增复杂 → 通过清晰注释和条件语句控制
