# Memory Diagnostics

跨平台内存异常分析工具，输出统一 JSON，用于快速判断内存压力来自进程、系统提交量、Docker 容器，还是 Windows 内核池/驱动服务线索。

## Usage

```powershell
Invoke-MemoryDiagnostics.ps1 snapshot
Invoke-MemoryDiagnostics.ps1 sample -IntervalSeconds 300 -Count 3
Invoke-MemoryDiagnostics.ps1 help
```

## Scope

- 只生成诊断报告，不关闭进程、不停服务、不修改注册表、不改 Docker restart policy。
- Windows 会采集 commit、pagefile、paged/nonpaged pool、运行中驱动和服务摘要。
- Linux/macOS 会采集系统内存摘要、swap 和 Top 进程，并在命令缺失时返回结构化 warning。
- Pool tag 级别归因需要 RAMMap、Process Explorer、Autoruns 或 PoolMon 等外部工具继续分析。
