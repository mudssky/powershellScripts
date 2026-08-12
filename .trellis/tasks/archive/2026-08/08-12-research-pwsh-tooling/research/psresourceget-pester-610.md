# PSResourceGet 与 Pester 6.1.0 研究

## 结论

本任务仅保留两个实施方向：

1. 将仓库支持路径中的 PowerShell 模块安装收敛到 `Microsoft.PowerShell.PSResourceGet`。
2. 将固定 Pester 版本从 6.0.1 升级到 6.1.0，并优先验证 6.1.0 原生并行 coverage；外层 coverage 分片仅保留为原生方案未通过门禁时的备用。

核对日期：2026-08-12。

## Install-PSResource 的实际优势

### 与仓库运行基线一致

`psutils/psutils.psd1` 要求 PowerShell 7.4。`Microsoft.PowerShell.PSResourceGet` 自 PowerShell 7.4 起内置，因此仓库无需为受支持运行时额外引入旧 PowerShellGet 2.x 作为模块安装基础设施。

### 一个资源模型覆盖模块和脚本

`Install-PSResource` 合并了 PowerShellGet v2 的 `Install-Module` 与 `Install-Script` 职责；同一组 `Find-PSResource`、`Get-InstalledPSResource`、`Update-PSResource`、`Uninstall-PSResource` 命令可以管理 PowerShell 资源。

### 声明式、可复现安装

`-RequiredResourceFile` 和 `-RequiredResource` 可以声明多个资源、版本范围、仓库和 prerelease 属性。对于本仓库，这比在 `installModules.ps1` 中只维护模块名数组更适合固定 Pester、PSReadLine、BurntToast 等模块版本和来源。

### 更明确的覆盖与供应链控制

- `-Version` 同时支持精确版本和 NuGet 风格版本范围。
- `-Reinstall` 明确表达覆盖已安装同版本。
- `-NoClobber` 明确阻止覆盖现有命令。
- `-TrustRepository`、`-AcceptLicense`、`-AuthenticodeCheck` 提供明确的仓库、许可和签名策略。
- `-PassThru` 可返回安装结果，便于包装函数输出结构化状态。
- `-WhatIf` / `-Confirm` 与仓库现有 `SupportsShouldProcess` 合同一致。

### 迁移不是命令改名

参数语义需要显式映射：

| PowerShellGet v2 | PSResourceGet | 迁移注意 |
|---|---|---|
| `-RequiredVersion 6.0.1` | `-Version 6.1.0` | `Version` 也接受范围，仓库必须继续传精确值 |
| `-Force` | `-Reinstall` | 仅在确实需要覆盖同版本时使用 |
| `-AllowClobber` | 默认允许；`-NoClobber` 阻止 | 语义方向相反，不能机械替换 |
| `-AllowPrerelease` | `-Prerelease` | 名称变化 |
| `-SkipPublisherCheck` | 无直接等价参数 | 不应静默伪造；需要明确仓库信任策略 |
| `-Proxy` / `-ProxyCredential` | 无对应安装参数 | 如仓库仍需显式代理，必须验证环境/HTTP 层策略 |

`Install-PSResource` 安装后不会自动把新模块载入当前会话。仓库现有 `Install-RequiredModule` 已显式执行 `Import-InstalledModule`，该合同应保留。

当前本机 `Microsoft.PowerShell.PSResourceGet` 为 1.2.0（当前稳定版）。1.3.0-preview1 才加入安装工作流并发，本任务不依赖 preview 能力，也不把“并行安装”列为当前收益。

## Pester 6.1.0 的实际价值

Pester 6.1.0 于 2026-08-11 发布为稳定版，支持 Windows PowerShell 5.1 和 PowerShell 7.4+。

相对仓库当前 6.0.1，直接相关的改进：

- `Run.Parallel` 可以跨 worker 收集并合并 code coverage，不再因为开启 coverage 必然退回串行。
- 修复并行运行中的并发模块导入崩溃。
- 并行 Detailed 输出恢复 `Describe` / `Context` 标题，并正确回放 Verbose/Debug 输出。
- discovery 失败的 container 会进入 TestResult XML，不再从报告中消失。
- coverage 可采集 `Invoke-InNewProcess` 子进程，并修复 steppable-pipeline proxy 的漏报。
- JUnit testsuite 增加 timestamp。

新能力 `Mock.Global`、`Run.Shuffle` 和自定义 `Should-*` assertion 均不属于本次升级目标；前两项是实验功能，默认不启用，避免扩大兼容面。

## 对现有任务的影响

`.trellis/tasks/08-12-design-pwsh-coverage-sharding/prd.md` 建立在“Pester 6.0.1 不支持并行 coverage”前提上。6.1.0 已改变该前提，因此：

1. 先升级固定版本并完成串行兼容。
2. 使用原生 `Run.Parallel + CodeCoverage` 做自动、2、4 throttle 对照。
3. 比较串行与并行的测试数、失败集合、Skip/NotRun、JaCoCo instruction/line 计数、NUnit test-case 集合、残留进程和三轮耗时。
4. 原生方案满足正确性与性能门禁时，暂停外层分片任务。
5. 原生方案不能满足门禁时，才恢复外层分片设计。

## 官方资料

- Microsoft Learn：`Install-PSResource` reference。
- Microsoft Learn：PSResourceGet release notes，当前稳定版 1.2.0。
- Pester 6.1.0 GitHub release notes。
- Pester v5 → v6 migration guide；现有 v5 assertion syntax 保持兼容。
