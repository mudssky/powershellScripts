# 升级 PSResourceGet 与 Pester 6.1.0

## Goal

将仓库支持路径中的 PowerShell 模块安装统一到 `Microsoft.PowerShell.PSResourceGet`，并把固定 Pester 版本从 6.0.1 升级到 6.1.0；优先验证 Pester 6.1.0 原生并行 coverage 能否在不降低正确性合同的前提下替代外层 coverage 分片方案。

## Background

- 用户只对 `Install-PSResource` 与 Pester 6.1.0 升级感兴趣，其他 Pwsh 生态候选全部退出本任务。
- `psutils/psutils.psd1` 的最低版本是 PowerShell 7.4；PSResourceGet 自 PowerShell 7.4 起内置，本机稳定版为 1.2.0。
- 仓库模块安装主路径仍通过 `Install-Module`：`psutils/modules/install.psm1`、`scripts/pwsh/devops/Install-Pester.ps1`，另有两个活动 misc 入口直接安装 Pester/PSScriptAnalyzer。
- 仓库已通过 `.pester-version`、runner、Dockerfile 和 CI 将 Pester 固定为 6.0.1，并保留 5.7.1 显式回退。
- Pester 6.1.0 于 2026-08-11 发布为稳定版，新增原生并行 coverage 合并，并修复并发导入、并行输出与报告问题。
- 现有 coverage 外层分片任务建立在 Pester 6.0.1 不支持并行 coverage 的前提上；该前提需先由 6.1.0 实测重新判断。

## Requirements

- R1：仓库活动代码中的 PowerShell Gallery 安装必须通过 PSResourceGet 或统一包装边界，不保留新的 `Install-Module` 双轨路径。
- R2：`Install-Module` 参数必须按语义迁移，不机械替换：精确版本映射到 `-Version`，覆盖同版本映射到 `-Reinstall`，不得把 `-AllowClobber`、`-SkipPublisherCheck` 伪装成不存在的等价参数。
- R3：安装后显式导入模块、`SupportsShouldProcess`、`-WhatIf`、逐模块结构化结果和失败后继续合同保持不变。
- R4：将 `.pester-version` 固定为 6.1.0；本机安装、Docker、CI、runner 和 duration artifact 必须继续读取同一版本事实来源。
- R5：保留 Pester 5.7.1 回退入口；不要求卸载本机已有 Pester 版本。
- R6：先验证 6.1.0 串行兼容，再验证原生 `Run.Parallel + CodeCoverage`；不启用 `Mock.Global`、`Run.Shuffle` 或自定义 assertion 等无关新能力。
- R7：并行 coverage 必须与串行基线比较测试发现数、失败集合、Skip/NotRun、NUnit test-case、JaCoCo instruction/line 计数、coverage 百分比和残留进程；不能只比较总耗时。
- R8：原生并行 coverage 通过正确性门禁后，才能考虑替换默认 full；未通过时保持串行默认，并恢复外层分片任务作为备用。
- R9：不降低 50% coverage 门槛，不扩大 coverage 排除范围，不删除真实入口、UTF-8、多流、Running、退出码或中断清理合同。

## Acceptance Criteria

- [x] 活动代码中不再直接调用 `Install-Module`；模块安装统一经过 PSResourceGet 边界，并有参数、WhatIf、安装后导入和失败继续测试。
- [x] `.pester-version` 为 `6.1.0`，安装脚本、Docker、CI、runner 和 duration reporter 均准确使用或记录该版本。
- [x] Pester 6.1.0 串行 QA、full assertions 与 coverage 运行完成；与 6.0.1/既有基线的差异有明确解释并由测试锁定。
- [x] Pester 6.1.0 原生并行 coverage 完成固定 throttle 2 的仓库级对照；候选同时失败 coverage 计数等价和 `<=270s` 性能门禁，按短路规则不再执行自动与 throttle 4。
- [x] 串行与并行 NUnit 测试集合均为 `965 total / 939 passed / 0 failed / 26 skipped`；串行 instruction `3011/1860`，并行 `3030/1841`，差异已记录且运行后无残留交互进程。
- [x] 原生并行 coverage 未通过门禁，默认入口保持串行，并明确继续外层分片任务。
- [ ] `pnpm qa` 与 `pnpm test:pwsh:all` 通过；若 Docker 不可用，至少执行 `pnpm test:pwsh:full` 并明确 Linux 覆盖依赖 CI/WSL。

## Out of Scope

- PSScriptAnalyzer lint 门禁、PlatyPS、SecretManagement、Crescendo 或其他终端工具。
- 启用 Pester 6.1.0 的 `Mock.Global`、`Run.Shuffle`、自定义 `Should-*` assertion。
- 在原生并行 coverage 结论出来前实施完整外层 JaCoCo/NUnit 分片合并。
- 修复与本任务无关的既有 WSL guest Windows 路径失败。

## Key Decisions

- 使用 PSResourceGet 当前稳定通道，不依赖 1.3.0 preview 的并行安装能力。
- Pester 目标版本固定为 6.1.0，不使用浮动 latest。
- 先以官方原生并行 coverage 为首选，外层分片降级为失败备用。
- 继续保留 5.7.1 回退入口，升级与默认入口提升分开验收。
