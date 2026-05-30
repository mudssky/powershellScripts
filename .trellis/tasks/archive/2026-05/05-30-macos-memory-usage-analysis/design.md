# macOS 内存诊断脚本优化设计

## Architecture And Boundaries

- 修改范围限定在 `scripts/pwsh/devops/memory-diagnostics` 与对应 Pester 测试。
- macOS 平台增强放在 `platforms/macos.ps1`，跨平台建议增强放在 `core/thresholds.ps1`，Docker Desktop VM 只读补充放在 `core/docker.ps1`。
- 不改变已有入口命令、参数和 JSON 顶层结构；新增字段必须向后兼容。
- 不停止进程、不修改 Docker Desktop 配置、不删除容器、不改登录项。

## Data Flow And Contracts

- `Get-MacOSPlatformSnapshot` 继续返回 `System`、`WindowsOnly`、`Warnings`。
- `System` 在现有字段基础上新增：
  - `memoryPressureFreePercent`
  - `vmPressureLevel`
  - `compressedGB`
  - `compressorGB`
  - `swapins`
  - `swapouts`
  - `pageins`
  - `pageouts`
  - `purgeableGB`
  - `wiredGB`
- `Get-MacOSTopMemoryProcesses` 改用宽输出 `ps -ww`，保留原 `ConvertFrom-MemoryDiagnosticsPsLine` 解析契约，避免进程名截断。
- `Get-DockerMemorySnapshot` 在 macOS 上额外读取 Docker Desktop 虚拟机启动参数中的 `--memoryMiB`，新增 `desktopVmMemoryLimitMB`、`desktopVmMemoryLimitGB`、`desktopVmProcessId`。
- `Get-MemoryDiagnosticsRecommendations` 根据新增 macOS 字段输出建议，不依赖非 macOS 平台必须存在这些字段。

## Important Trade-offs

- `memory_pressure` 的“free percentage”更接近即时压力信号，`vm_stat` 的 free/inactive/speculative 更接近可回收估算；报告保留两者，建议层优先解释压力而非单纯已用内存。
- Docker Desktop VM 上限从进程命令行解析，属于 best-effort 字段；解析失败只给 warning 或空值，不中断报告。
- 容器实际使用与 VM 上限同时展示，避免误把容器 2.5GB 使用量和 VM 8GB 上限混为一谈。

## Compatibility

- Windows/Linux 字段和推荐规则保持现有语义。
- 新增字段只追加，不删除 `totalPhysicalGB`、`availableGB`、`usedPhysicalGB`、`availablePercent`、`swap*` 等既有字段。
- Pester 测试使用解析函数的固定样本，不依赖当前机器必须运行 Docker。

## Operational Notes

- 修改 PowerShell 脚本后运行 `pnpm qa`。
- 因改动涉及 `scripts/pwsh/**`，按项目规则额外运行 `pnpm test:pwsh:all`；如果 Docker 不可用，则至少运行 `pnpm test:pwsh:full` 并说明 Linux 覆盖依赖 CI 或 WSL。
