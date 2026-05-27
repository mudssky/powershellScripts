# 内存异常分析脚本设计

## Architecture

工具采用目录型 PowerShell CLI：

```text
scripts/pwsh/devops/memory-diagnostics/
  main.ps1
  tool.psd1
  README.md
  core/
    report.ps1
    process.ps1
    docker.ps1
    sampling.ps1
    thresholds.ps1
  platforms/
    windows.ps1
    linux.ps1
    macos.ps1
```

`main.ps1` 只负责参数解析、加载模块、调用报告构建函数和输出 JSON。平台采集逻辑放在 `platforms/`，跨平台归一化和阈值判断放在 `core/`。

## Public Interface

推荐入口：

```powershell
Invoke-MemoryDiagnostics.ps1 snapshot [-Top 30] [-Depth basic|full] [-JsonDepth 8]
Invoke-MemoryDiagnostics.ps1 sample [-IntervalSeconds 300] [-Count 3] [-Top 30]
Invoke-MemoryDiagnostics.ps1 help
```

第一版默认命令可等价于 `snapshot`，便于直接运行。

## Report Contract

统一输出对象：

```text
metadata
system
topProcesses
containers
windowsOnly
samples
warnings
recommendations
```

`recommendations` 是结构化建议字段，基于阈值和缺失能力生成，不执行任何修改动作。

第一版 recommendations 至少覆盖：

- 高进程占用：提示优先关注 Top 进程和工作集/私有内存。
- Windows commit/kernel pool 异常：提示不要只看进程列表，并建议使用 RAMMap、Process Explorer、Autoruns、PoolMon 等外部工具继续归因。
- Docker 线索：当 Docker 占用不突出或不可用时，明确标注其状态，避免误把容器当作唯一主因。

## Platform Strategy

- Windows：优先使用 CIM 与 `Get-Process`，采集 commit、commit limit、paged/nonpaged pool、驱动和服务摘要。
- Linux：优先读取 `/proc/meminfo`，Top 进程使用 `ps`；缺少命令时写入 `warnings`。
- macOS：使用 `sysctl`、`vm_stat`、`memory_pressure`、`ps`；缺少命令时降级。
- Docker：通过 `docker stats --no-stream --format json` 或可解析格式采集；不可用时返回状态。
- Recommendations：基于归一化报告生成，保持独立于平台采集函数，方便测试阈值逻辑。

## Boundaries

- 工具只做诊断报告，不关闭进程、不停服务、不修改注册表、不改 Docker restart policy。
- Pool tag 级别归因只输出外部工具建议。
- 可复用的稳定基础函数后续再迁入 `psutils`，第一版先保持在工具目录内，避免公共模块过早扩张。

## Testing Strategy

- 平台采集函数尽量拆成“原始命令输出解析”和“命令调用”两层，测试解析和结构归一化。
- Pester mock Docker、CIM、`ps` 输出，覆盖命令不可用和权限不足。
- 入口测试验证 help、snapshot JSON、sample 参数边界和 `tool.psd1` 可发现性。
