# PowerShell 全量测试耗时研究

## 测量环境

- 平台：Windows
- PowerShell：Pester 5.7.1，通过 `pwsh -NoProfile`
- 基线入口：`pnpm test:pwsh:full`
- 基线规模：75 files，927 tests
- 基线结果：693.9 秒测试阶段，命令总计约 718.6 秒，coverage 62.39% / 50%
- 单文件复测入口：`Invoke-PesterMode.ps1 -Mode full -Coverage Off -VerboseOutput -Path <file>`

## 文件级热点

| 文件 | 全量 coverage 日志 | 单文件 coverage off | 主因 |
|---|---:|---:|---|
| WindowsInstallPipeline.Tests.ps1 | 223.59s | 253.47s | 缺失命令自动发现、重复 WhatIf/verify 子进程 |
| LinuxInstallPipeline.Tests.ps1 | 79.89s | 77.99s | 14 个独立 pwsh/bash 入口重复加载模块与配置 |
| InstallOrchestrator.Tests.ps1 | 78.91s | 80.05s | 状态机测试重复启动多步 fixture 叶子进程 |
| MacOSInstallPipeline.Tests.ps1 | 54.25s | 50.45s | 9 个独立 pwsh 入口重复加载模块与配置 |
| apiBoundary.Tests.ps1 | 35.43s | 33.06s | 动态用例反复卸载并导入聚合/子模块 |

单文件关闭 coverage 后与 full 日志接近，因此这些热点主要不是 coverage 插桩导致。

## Windows 详细证据

- 多叶子 WhatIf：76.79s
- ARM64/Server 两次平台分类：35.82s
- Core CLI WhatIf：26.98s
- 99 JSON：25.91s
- WSL WhatIf：20.95s
- Windows 10/11 分类：32.28s
- verify JSON：17.21s

全新进程命令发现样本：

| 命令 | 耗时 |
|---|---:|
| Get-WinGetSource | 2945.9ms |
| Add-WinGetSource | 2328.7ms |
| Remove-WinGetSource | 2327.0ms |
| AutoHotkey.exe | 4580.2ms |
| winget/pwsh/scoop/wsl | 合计约 30ms |

`Get-WindowsInstallEnvironment` 的测试夹具未覆盖全部命令名时，会回退到真实 `Get-Command`，使纯分类测试变成昂贵的环境集成测试。05/06/07/08/09、verify 和 WSL 入口也会在各自新进程中重新构建能力模型。

## 优化方向

1. 为 Windows 单元测试提供完整 command availability fixture，真实命令发现只保留一个明确标记的集成用例。
2. 将跨平台清单选择、平台模型和结果聚合优先放在模块内直接调用测试；每个入口只保留参数解析、JSON 单文档和退出码 smoke。
3. 在编排器测试中 Mock 私有 `Invoke-InstallLeafProcess` 验证状态机；真实进程只保留 UTF-8 字节、多流、启动提示与中断进程树合同。
4. `apiBoundary` 共享一次聚合模块导入，批量验证 diagnostic visibility；避免每个动态 case 重复完整 import/remove。
5. 不依赖当前无效的 `Run.Parallel` 配置。Pester 5.7.1 的 `Run` 对象没有 `Parallel` 属性，拆文件不会自动获得 4 路调度；应直接减少子进程和重复导入。若未来引入外层分片 runner，需要单独设计 coverage 合并。
6. 复用现有 duration reporter，增加 NUnit3/JSON 持久化、单用例 Top N 和总阶段耗时，避免后续重新人工解析日志。

## psutils 命令发现实验

仓库已有 `psutils/modules/commandDiscovery.psm1`，公共函数为 `Find-ExecutableCommand`，无需再创建同类封装。

- 3 轮全新 `pwsh -NoProfile`，命令集合为 `winget/pwsh/scoop/wsl/AutoHotkey.exe`。
- `Find-ExecutableCommand` 纯探测平均 569.9ms。
- `Get-Command` 平均 4817.8ms。
- 纯探测加速约 8.45x。
- 把直接模块导入计入后，3 个完整样本为 752.8ms、713.3ms、741.0ms，仍比 `Get-Command` 快约 6.5x。
- 实际结果正确识别本机 winget.exe、pwsh.exe、scoop.cmd、wsl.exe，并将未安装的 AutoHotkey.exe 返回为 missing。

限制：`Find-ExecutableCommand` 只扫描 PATH/PATHEXT，不能替代 `Get-WinGetSource`、`Add-WinGetSource`、`Remove-WinGetSource` 等 PowerShell cmdlet。3 个名字以数组传给 `Get-Command` 仍平均约 7615ms；一次 `Get-Module -ListAvailable Microsoft.WinGet.Client` 平均约 2693ms，因此应采用模块级能力探测并在测试中提供完整 fixture。

## 风险

- 过度 Mock 会漏掉入口脚本参数、`exit`、流污染和真实进程清理问题，因此必须保留少量端到端 smoke。
- 当前 Pester 调用按 container 串行执行；若未来引入外层并行分片，必须先隔离环境变量、模块状态、fixture 路径和报告输出，并解决 coverage 合并。
- Docker/WSL lane 需要独立计时，不能与 Windows host 数字合并。

## 实施后测量

以下均为 Windows host、Pester 5.7.1、coverage off 的独立单文件样本；并发执行造成报告锁冲突的样本不计入性能结论。

| 文件 | 优化前 | 优化后 | 结果 |
|---|---:|---:|---|
| WindowsInstallPipeline + 必要 entry smoke | 253.47s | 约 40.87s | unit 17.47s；entry 23.40s；全部通过 |
| LinuxInstallPipeline.Tests.ps1 | 77.99s | 约 27-31s | 24 passed，2 个非 Linux skip |
| InstallOrchestrator.Tests.ps1 | 80.05s | 9.23s | 29 passed |
| MacOSInstallPipeline.Tests.ps1 | 50.45s | 17.03s | 9 passed，6 个非 macOS skip |
| apiBoundary.Tests.ps1 | 33.06s | 9.41s | 14 passed |

首次中间态 full assertions 在后续 Linux/macOS/Windows 入口收缩前运行：Discovery 17.85s，Run 541.3s，命令总耗时 546.5s。结果为 909 passed、3 failed、26 skipped、11 not run；2 个失败来自并行 browser-debug 任务，另 1 个是既有 WSL guest Windows 路径解析。该样本只用于定位剩余热点，不能作为最终验收样本。

最终使用 `pnpm test:pwsh:coverage:slowest` 连续采集 3 个独立 NUnit3/JSON artifact：

| 样本 | 墙钟 | Pester Run | 结果 |
|---|---:|---:|---|
| `pester-duration-2026-08-11T12-17-46-305Z.json` | 329.48s | 305.20s | 909 passed / 3 failed / 26 skipped |
| `pester-duration-2026-08-11T12-24-29-764Z.json` | 322.49s | 298.95s | 911 passed / 1 failed / 26 skipped |
| `pester-duration-2026-08-11T12-30-26-727Z.json` | 298.67s | 277.14s | 911 passed / 1 failed / 26 skipped |

墙钟中位数为 322.49 秒，最慢值为 329.48 秒，相对 718.6 秒基线改善 55.12%，满足 `<= 360s` 和至少改善 40% 的目标。JaCoCo 根 counter 为 INSTRUCTION covered=2943、missed=1769，即 62.46%，高于 50% 门槛。

第 1 轮执行期间并行的 browser-debug 工作区改动尚未稳定，因此包含 2 个该任务失败；后两轮 browser-debug 已通过。3 轮共同剩余的失败是既有 `WSL SSH 宿主与客体入口合同.guest 测试模式输出零副作用单文档 Preview` Windows 路径解析问题，与本任务改动无关。样本期间工作区并非完全静态，这是本组数据的限制；性能数值仍连续 3 轮低于目标上限。

独立审查修复 `zsh` runner、AutoHotkey fallback、WinGet snapshot 和不完整 fixture 合同后，又执行了一轮最终 coverage full：墙钟 342.08 秒，Pester Run 321.37 秒，914 passed / 1 failed / 26 skipped，coverage 62.46%。唯一失败仍为上述既有 WSL guest 路径用例，说明审查修复未扩大失败集合，耗时仍低于 360 秒。

### Pester 并行配置纠偏

`New-PesterConfiguration` 生成的 Pester 5.7.1 `Run` 对象没有 `Parallel` 属性。仓库旧配置中的 `Run.Parallel = @{ Enabled = ...; MaxThreads = 4 }` 未形成并行执行，控制台也按 container 串行运行。因此：

- 单纯拆分 `.Tests.ps1` 不会缩短当前 full 时长，还会增加 discovery 和 BeforeAll 成本。
- 本次实际收益来自模块内断言、共享导入、完整 command fixture 和进程边界 test hook。
- 若未来需要并行，必须在 Pester 外层分片，并先设计 NUnit/coverage 合并与唯一输出路径。

## 最终策略结论与后续方向

本轮确认有效的主要策略按收益排序如下：

1. 减少重复真实 `pwsh`/`bash`/`zsh` 子进程，把清单选择、平台分类和状态机分支迁移到模块内测试。
2. 对编排器 Mock 稳定进程边界，仅保留 UTF-8、多流、单次 `[Running]`、退出码和中断进程树等真实进程合同。
3. Windows 外部命令复用 `Find-ExecutableCommand` 批量扫描 PATH/PATHEXT；该探测比 `Get-Command` 快约 6.5-8.45 倍。
4. 使用完整 `CommandAvailability` fixture 阻止单元测试静默回退宿主扫描；WinGet cmdlet 使用会话级模块能力 snapshot。
5. 聚合模块和大型 fixture 在 `BeforeAll` 共享，避免动态用例反复完整 import/remove。
6. 每轮性能测试使用唯一 NUnit3/JSON 路径；Docker 不可用时在启动 host lane 前快速失败。

当前剩余热点以最终 coverage full 为参考：

| 优先级 | 文件 | 典型耗时 | 后续实验 |
|---|---|---:|---|
| P1 | `psutils/tests/install.Tests.ps1` | 25-33s | 检查未 Mock 的 `Install-Module`、仓库查询和命令发现边界 |
| P1 | `tests/WindowsInstallEntrypoint.Tests.ps1` | 21-25s | 在保留真实入口合同的前提下聚合进程 smoke |
| P1 | `tests/LinuxInstallPipeline.Tests.ps1` | 23-26s | 继续分离模块合同与必要入口进程 |
| P2 | `tests/PackageSources.Tests.ps1` | 17-29s | 定位事务 fixture、模块导入和文件系统初始化波动 |
| P2 | `docker.Tests.ps1`、`Install.Tests.ps1`、`moduleContract.Tests.ps1` | 16-18s | 减少目录扫描、重复导入和宿主探测 |

下一阶段应先做串行路径优化，现实目标为 Windows host coverage-on 三轮中位数 260-290 秒。只有目标要求显著低于 240 秒时，才考虑 Pester 外层分片；该方案必须同时实现 coverage 合并、NUnit 汇总、TestDrive 和环境变量隔离。
