# 技术设计

## 目标与边界

目标是在不减少合同覆盖和不降低 50% coverage 门槛的前提下，把 Windows host `pnpm test:pwsh:full` 从约 718.6 秒降到 6 分钟以内。优化对象是测试执行架构和可复用命令发现，不改变真实安装顺序、包清单、退出码或平台支持矩阵。

## 设计概览

```text
Pester full
  -> unit containers: 模块内纯逻辑、完整 test doubles、无真实环境扫描
  -> entrypoint containers: 少量真实 pwsh/bash 进程，验证参数/JSON/exit
  -> process-contract containers: 字节流、启动提示、中断和进程树清理
  -> NUnit3 + duration artifact: 文件/It/阶段耗时和环境元数据
```

### 1. Windows 命令能力快照

- 保留 `Get-WindowsInstallEnvironment -CommandAvailability <hashtable>` 测试注入合同。
- 新增或收敛一个内部批量能力解析函数，一次返回 Windows 安装所需命令 map。
- PATH 外部命令使用直接导入的 `Find-ExecutableCommand -Name <array> -CacheMisses`，不导入完整 `psutils` 聚合模块。
- WinGet source cmdlet 通过一次 `Get-Module -ListAvailable Microsoft.WinGet.Client` 获取模块能力，再检查导出命令；不逐个执行缺失命令的 `Get-Command` 自动发现。
- AutoHotkey 保留已知安装路径 fallback；PATH 命令结果与路径 fallback 合并，不改变现有语义。
- 同一进程内复用能力快照；测试平台矩阵必须提供完整 map，真实环境探测只留一个集成 smoke。

### 2. 测试分层

#### Unit

- 平台模型、清单选择、结果聚合、事务状态和 verify 名称来源直接调用模块函数。
- 外部命令、环境读取和进程执行全部通过现有参数注入或 Pester Mock 隔离。

#### Entrypoint Integration

- 每个平台保留最少入口 smoke，覆盖互斥参数、`-WhatIf`/dry-run、JSON 单文档和退出码。
- 不再为每个清单分类重复启动一个完整 PowerShell 进程；清单精确集合由 unit 层锁定。
- Pester 5.7.1 的 `Run` 配置没有 `Parallel` 属性；仓库原先写入的 `Run.Parallel` 键不会形成 4 路 container 调度。性能收益必须来自减少真实进程、复用模块导入和缩窄入口 smoke，而不是仅拆文件。
- unit/entrypoint 仅在职责隔离或 fixture 边界确有价值时拆分；串行运行下应避免为了“并行”增加 discovery 与重复 BeforeAll 成本。

#### Process Contract

- `InstallOrchestrator` 的 UTF-8 原始字节、多流复制、单次 Running 提示和中断进程树继续使用真实子进程。
- 依赖传播、Preview/Failed/Blocked、source transaction、restore 优先级和重跑命令通过 Mock 私有 `Invoke-InstallLeafProcess` 返回稳定结果。
- Mock 必须断言调用参数与次数，不能只断言最终 document。

### 3. API Boundary 导入复用

- 聚合 manifest 的 visibility 验证只导入一次，并在同一用例或共享 `BeforeAll` 中批量检查 diagnostic 命令。
- 子模块导出测试只加载目标模块；避免每个动态 case 先导入并移除完整 psutils。
- 公共函数帮助合同继续遍历全部导出函数，不降低函数文档要求。

### 4. 全量入口和 Docker 预检

- `test:pwsh:all` 在启动 host/linux 并发门禁前检查 Docker CLI 与 daemon/compose 可用性。
- Docker 不可用时快速失败并明确提示运行 `pnpm test:pwsh:full`；不得先启动一个最终无法形成 all 结果的长 host lane。
- 外层中断或超时必须终止整个命令进程树，避免残留 Pester 和 fixture 子进程。

### 5. 耗时 Artifact

- 复用 `PESTER_RESULT_PATH` 为每次 host 测量分配唯一 NUnit3 路径，避免并行任务覆盖默认 `testResults.xml`。
- 扩展当前 Node duration reporter，输出 JSON artifact：命令、平台、pwsh/Pester 版本、开始/结束时间、退出码、Discovery/Run/Coverage 阶段、文件 Top N、test-case Top N。
- `test:pwsh:all` 的 host/linux lane 分开记录，不合并成一个不可解释的数字。
- 性能验收采用 3 次同机 coverage-on 样本的中位数和最慢值；Pester 单元测试不写易抖动的绝对秒数硬断言。

## 兼容性

- `test:pwsh:full`、`test:pwsh:coverage`、`test:pwsh:all` 的功能语义和 coverage 门槛不变。
- 快速命令发现只替代外部应用存在性探测，不用于函数、alias 或 PowerShell cmdlet。
- 所有平台合同仍在 full 中自动执行；测试分层不是增加 `Skip` 或转人工。

## 风险与回滚

- 风险：过度 Mock 漏掉脚本入口问题。缓解：每个平台保留入口 smoke，并让 JSON/exit/参数错误继续走真实进程。
- 风险：模块能力判断与实际导出漂移。缓解：为 WinGet module present/missing/export drift 建 fixture 测试，并保留一个真实探测 smoke。
- 风险：未来引入外层并行 runner 后环境变量或文件冲突。缓解：全部使用 TestDrive/唯一临时目录，环境变量在 AfterEach/AfterAll 恢复；当前 Pester 5.7.1 单次调用仍按 container 串行运行。
- 回滚：各文件优化可独立回退；package script 预检和 reporter 不改变 Pester 配置核心合同。
