# 内存异常分析脚本

## Goal

新增一个可复用的 PowerShell 内存异常分析工具，用统一 JSON 输出帮助定位普通进程占用、系统提交量、swap/pagefile、Docker/容器占用，以及 Windows 专属的内核池、服务和驱动线索。

该工具主要服务本机排障和后续可审计记录：先快速回答“内存到底被谁吃掉了”，再给出是否需要转向 RAMMap、Process Explorer、Autoruns、PoolMon 等外部工具的判断依据。

## Confirmed Facts

- 推荐主目录为 `scripts/pwsh/devops/memory-diagnostics/`，因为这是运维诊断型主工具，不适合放进 `misc`。
- 公开入口应使用目录型工具模式：`tool.psd1` 暴露 `BinName` 与 `Entry`，由 `Manage-BinScripts.ps1` 生成 `bin/` shim。
- 第一版主入口建议为 `Invoke-MemoryDiagnostics.ps1`，源码入口为 `main.ps1`。
- `psutils/modules/hardware.psm1` 已有基础系统/GPU内存信息能力，但当前需求更像异常分析 CLI，不应一开始把所有逻辑塞进该模块。
- 如果后续出现可被多个脚本复用的稳定采集函数，再考虑沉到 `psutils`。
- Windows 是主要高价值平台，需要覆盖进程、提交量、分页文件、paged/nonpaged pool、运行中系统驱动和服务线索。
- Linux/macOS 可以提供统一结构的基础采集，但深度弱于 Windows，主要包装 `/proc/meminfo`、`ps`、`vm_stat`、`memory_pressure` 等系统命令。

## Requirements

- 在 `scripts/pwsh/devops/memory-diagnostics/` 下实现目录型 PowerShell 工具。
- 通过 `tool.psd1` 暴露单一公开入口，避免内部 `core/`、`platforms/` 脚本直接进入 `bin/`。
- 输出统一 JSON，至少包含：
  - `system`: 总内存、可用内存、swap/pagefile、commit 或平台等价指标。
  - `topProcesses`: 默认 Top 30 进程，包含进程名、PID、Working Set/RSS、Private/VSZ 或平台等价指标。
  - `containers`: Docker 可用时采集容器内存；Docker 不可用时输出可审计的不可用原因。
  - `windowsOnly`: Windows 平台采集内核池、提交量、运行中驱动、服务线索。
  - `samples`: 支持间隔采样，用于观察疑似泄漏趋势。
  - `recommendations`: 根据阈值和缺失能力输出结构化结论/建议。
- Windows 平台必须能识别“进程总和不高但 kernel pool/commit 异常”的场景，避免只给进程列表。
- 第一版必须包含 `recommendations`，用于快速提示进程占用、commit、kernel pool、Docker 表象和外部工具下一步排查方向。
- 脚本应优先使用 PowerShell/CIM 与系统自带命令；Pool tag 级别诊断只给出外部工具建议，不在第一版强制依赖 WDK/PoolMon。
- 代码注释使用中文，仅解释复杂业务逻辑和设计意图；公共函数包含标准参数与返回值说明。
- 涉及 PowerShell 脚本逻辑时，按项目规则执行 `pnpm qa` 和 `pnpm test:pwsh:all`；若 Docker 不可用，至少执行 `pnpm test:pwsh:full` 并说明 Linux 覆盖依赖 CI 或 WSL。

## Acceptance Criteria

- [ ] `scripts/pwsh/devops/memory-diagnostics/tool.psd1` 能被 `Manage-BinScripts.ps1` 发现，并只暴露一个公开入口。
- [ ] `main.ps1` 支持一次性快照输出 JSON，默认不需要管理员权限也能返回可用的基础报告。
- [ ] Windows 报告包含 available、commit、commit limit、paged pool、nonpaged pool、kernel pool 等系统层指标。
- [ ] Windows 报告包含运行中驱动/服务摘要，且不会因为权限不足导致整个报告失败。
- [ ] Linux/macOS 至少返回系统内存摘要和 Top 进程，并在缺少某个系统命令时给出结构化降级信息。
- [ ] Docker 不存在、未运行或命令失败时，`containers` 字段保留状态与错误原因，不中断主报告。
- [ ] 采样模式可配置间隔和次数，并把每次采样写入统一 JSON 结构。
- [ ] `recommendations` 能提示至少三类方向：高进程占用、Windows commit/kernel pool 异常、Docker 不可用或疑似非主因。
- [ ] 相关业务逻辑有 Pester 覆盖，重点测试 JSON 结构、阈值判断、平台降级和 Docker 不可用场景。

## Out Of Scope

- 第一版不实现 Pool tag 归因，不安装 WDK，不自动解析 RAMMap/PoolMon 导出。
- 第一版不做自动清理、停服务、禁启动项或修改 Docker restart policy。
- 第一版不做常驻后台 daemon；采样是前台命令执行。
- 第一版不做图形化界面或 HTML 报告，除非后续明确扩展。

## Open Questions

- 无。已确认第一版包含 `recommendations` 结论/建议字段。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
