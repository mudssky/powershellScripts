# 优化 PowerShell 全量测试耗时

## Goal

定位并优化 `pnpm test:pwsh:full` / `pnpm test:pwsh:all` 的主要耗时来源，在不降低行为覆盖、coverage 门槛和跨平台安装流水线合同的前提下，缩短开发者本地提交前门禁的等待时间，并保留可重复的分项耗时诊断能力。

## Background

- 2026-08-11 Windows 本机执行 `pnpm test:pwsh:full`：Discovery 75 个文件、927 个测试，Discovery 10.21 秒，测试阶段 693.9 秒，coverage 处理后总命令约 718.6 秒。
- 该次结果为 889 passed、1 failed、26 skipped、11 not run；coverage 62.39%，门槛 50%。唯一失败来自本机 WSL guest 脚本路径解析，不属于安装输出修复任务。
- 已观察到的长测试文件包括：`WindowsInstallPipeline.Tests.ps1` 223.59 秒、`LinuxInstallPipeline.Tests.ps1` 79.89 秒、`InstallOrchestrator.Tests.ps1` 78.91 秒、`MacOSInstallPipeline.Tests.ps1` 54.25 秒、`apiBoundary.Tests.ps1` 35.43 秒、`install.Tests.ps1` 28.61 秒。
- `pnpm test:pwsh:all` 当前并发运行 host full assertions 与 Docker Linux full；本机 Docker CLI 不可用时，Linux 分支无法形成有效覆盖结果。
- 仓库已有 `test:pwsh:all:slowest`、`test:pwsh:assertions:slowest`、`test:pwsh:coverage:slowest` 文件级报告入口，但当前依赖解析彩色控制台摘要，不持久化结构化样本，也不能定位单个 `It` 的耗时。

## Confirmed Hotspots

- `WindowsInstallPipeline.Tests.ps1` 在关闭 coverage 后仍耗时 253.47 秒，证明 coverage 不是该文件主因。6 组热点合计约 236.7 秒：多叶子 WhatIf 76.79 秒、3 个平台分类用例 68.10 秒、Core CLI WhatIf 26.98 秒、99 JSON 25.91 秒、WSL WhatIf 20.95 秒、verify JSON 17.21 秒。
- Windows 平台分类函数每次最多执行 8 类真实命令发现。全新 `pwsh -NoProfile` 中，缺失的 `Get-WinGetSource`、`Add-WinGetSource`、`Remove-WinGetSource` 各耗时约 2.3–2.9 秒，缺失的 `AutoHotkey.exe` 探测约 4.6 秒。测试未提供完整 `CommandAvailability` 时，一次纯分类调用会重复支付约 12 秒模块自动发现成本。
- `LinuxInstallPipeline.Tests.ps1` 关闭 coverage 后耗时 77.99 秒，其中 14 个独立 `pwsh`/bash 入口占约 72 秒：05/08 WhatIf 22.03 秒、06/07 组合 24.33 秒、5 个 verify 21.73 秒、4 个互斥参数入口约 4 秒。
- `InstallOrchestrator.Tests.ps1` 关闭 coverage 后耗时 80.05 秒。注册表纯逻辑约 0.8 秒；执行块中约 13 个状态机用例各自真实启动叶子进程，单例 4–8 秒，累计约 75 秒。只有字节边界、启动提示、中断进程树等少数合同必须依赖真实子进程。
- `MacOSInstallPipeline.Tests.ps1` 关闭 coverage 后耗时 50.45 秒，9 个独立入口占约 40.6 秒：3 个安装叶子预览 18.06 秒、3 个只读 helper 17.22 秒、Profile Tools WhatIf 5.29 秒。
- `apiBoundary.Tests.ps1` 关闭 coverage 后耗时 33.06 秒。主要成本是为动态用例反复卸载并导入聚合模块/子模块；4 个 Diagnostic 用例每次重新导入完整 `psutils` manifest，单例约 2.6–6.5 秒。
- 结论：主要瓶颈不是 Discovery（约 10 秒）、普通断言或 coverage 收尾，而是测试容器内串行重复的真实进程启动、模块导入、缺失命令自动发现和完整 fixture 执行。

## Requirements

1. 建立可复现的测试耗时基线，至少区分 Discovery、Run、coverage processing、测试文件和跨平台 host/linux 分支。
2. 查明前述长测试文件的具体慢点，区分真实 `Start-Sleep`/轮询、重复启动 `pwsh`/bash/WSL 子进程、重复 fixture 仓库复制、模块导入、Mock 边界和 coverage 插桩成本。
3. 优化不得删除关键行为断言、降低 50% coverage 门槛、跳过 Windows/Linux/macOS 安装流水线合同，或把本应自动执行的门禁改成人工验证。
4. 优先采用测试结构优化、可注入时钟/轮询、共享 fixture、缩窄稳定 coverage 路径和合理测试分层；不得用放宽超时或静默跳过掩盖慢点。
5. 保持本地与 CI 的职责清晰：Docker/WSL 不可用时要有明确行为，不让缺失运行时造成长时间无反馈或残留进程。
6. 为优化前后提供同机、同入口、相同 coverage 配置下的对比数据，并记录不能稳定本地复现的 Linux/Docker 部分。
7. Windows 外部命令发现优先复用 psutils 已有的 `Find-ExecutableCommand` 批量接口，不新增同类 wrapper；PowerShell cmdlet 能力通过一次模块级探测或测试夹具提供，不再逐命令触发模块自动发现。
8. Windows 本机 `pnpm test:pwsh:full` 优化后 3 次样本中位数必须不超过 6 分钟，且相对约 718.6 秒基线至少改善 40%。

## Acceptance Criteria

- [ ] 输出按测试文件排序的耗时报告，并解释前五个热点的直接原因与调用路径。
- [ ] 给出 `pnpm test:pwsh:full` 总耗时的优化前基线和优化后至少 3 次样本，报告中位数、最慢值及环境信息。
- [ ] 优化后所有受影响的 Pester 用例通过，coverage 仍不低于 50%。
- [ ] `pnpm qa` 通过；Docker 可用时 `pnpm test:pwsh:all` 通过，Docker 不可用时 `pnpm test:pwsh:full` 通过并明确 Linux 覆盖依赖 CI/WSL。
- [ ] 不再因门禁超时留下 `pnpm`、Pester 或安装 fixture 子进程树和 `.install-tests.*` 测试目录。
- [ ] 形成可复用的性能诊断入口或结构化 artifact，后续可以定位新增慢测试而无需人工解析彩色控制台日志。
- [ ] `Find-ExecutableCommand` 在 Windows 安装能力探测中的命中语义有回归测试；不得把 PATH 可执行文件、PowerShell cmdlet 和已知安装路径混为同一种发现机制。

## Out of Scope

- 降低测试覆盖范围、删除跨平台合同或降低 coverage 门槛。
- 优化被测安装脚本的真实网络下载或真实包管理器性能。
- 要求开发机必须安装 Docker Desktop；Linux 容器门禁可继续由 CI/WSL 承担。

## Key Decisions

- 性能目标为 host full coverage 中位数不超过 6 分钟且至少改善 40%，因此范围包含测试分层和进程边界 Mock，不只做局部命令发现替换。
- 复用 `psutils/modules/commandDiscovery.psm1` 的 `Find-ExecutableCommand`。3 轮冷启动 benchmark 中，5 个 Windows 外部命令平均 569.9ms，对照 `Get-Command` 4817.8ms；包含直接模块导入后的 3 个样本为 713.3–752.8ms。
- `Find-ExecutableCommand` 只处理 PATH 外部命令；3 个 WinGet source cmdlet 继续按模块能力判断。简单数组批量 `Get-Command` 仍约 7.6 秒，不作为优化方案。
- 端到端入口用例只保留参数解析、JSON 单文档、退出码、真实流和进程清理等边界合同；清单选择、状态聚合、事务传播和平台矩阵转为模块内测试或 Mock 进程边界。
- 本任务保持单个 Trellis 任务：各优化共享同一 6 分钟目标与全量回归门禁，拆成独立子任务会增加重复基线和集成验收成本。
