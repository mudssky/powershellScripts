# 技术设计

## 目标与阶段边界

本任务分为两个顺序门禁：

1. 串行热点优化：继续使用当前可复现的 Pester 5.7.1 基线，把 Windows coverage full 三轮中位数压到 290 秒以内。
2. Pester 6 兼容与 assertions 并行：在独立开关下升级到稳定版 6.0.1，验证串行兼容、文件级并行隔离和 NUnit 合同。

阶段二依赖阶段一完成。不得用并行掩盖仍可消除的真实网络、模块发现或重复子进程成本。

## 版本与入口设计

### 版本选择

- 新增一个仓库级 Pester 版本常量或等价配置源，默认目标版本为 `6.0.1`。
- 本机安装入口、Dockerfile 和 CI 必须读取同一固定版本，不再无版本执行 `Install-Module Pester`。
- `Invoke-PesterMode.ps1` 在创建配置前显式导入目标 Pester 版本，避免模块自动加载选择机器上的任意版本。

### 运行开关

- `PWSH_PESTER_VERSION`：覆盖要导入的 Pester 版本，用于 5.7.1 回退和 6.0.1 PoC。
- `PWSH_TEST_PARALLEL`：显式启用 Pester 6 文件级并行；未设置时保持串行。
- `PWSH_TEST_PARALLEL_THROTTLE`：可选正整数；未设置时保留 Pester 6 的自动值 `0`。仓库完整诊断 PoC 入口固定为已验证的 `2`，自动、2、4 三档正式性能对照转入后续优化任务。
- 请求并行但目标 Pester 不支持 `Run.Parallel` 时必须明确失败，不能静默退回串行并产生虚假性能结论。

最终保留以下可观察入口：

```text
test:pwsh:full            -> 保持 Pester 6 串行 coverage full
test:pwsh:full:serial     -> Pester 6 串行 coverage full
test:pwsh:full:pester5    -> Pester 5.7.1 串行回退
test:pwsh:full:parallel:poc -> Pester 6 assertions 文件级并行 PoC
```

并行 PoC 未通过前，`test:pwsh:full` 仍映射到串行入口。

## 阶段一：串行热点优化

### install.Tests

- 将 `Install-Module`、PowerShell Gallery 查询和模块存在性探测视为外部边界。
- 状态机与调用次数使用 Mock；仅保留一个显式集成 smoke 验证真实命令绑定，不访问网络。
- 不允许测试中的伪模块名触发真实 PSGallery 查询。

### 平台入口 smoke

- Windows/Linux 入口继续验证参数解析、单文档 JSON 和退出码。
- 能在同一个真实进程内验证的多个只读场景允许通过 harness 聚合，但生产入口本身至少保留一次直接执行。
- 平台清单、分类和 verify 名称继续放在模块内测试，不回退宿主发现。

### 其他热点

- `PackageSources.Tests.ps1` 共享事务 fixture 和模块导入，记录冷/热样本定位 17-29 秒波动。
- `docker.Tests.ps1`、`Install.Tests.ps1`、`moduleContract.Tests.ps1` 和 documentation 测试减少重复目录扫描和 manifest 导入。

## 阶段二：Pester 6 并行 PoC

### 兼容性矩阵

先在 Pester 6 串行模式执行受影响窄测、QA 和 full，比较：

- discovery/test 数量和 Skip/NotRun 语义
- Mock、`InModuleScope`、BeforeDiscovery/BeforeAll 生命周期
- NUnit3 suite/test-case 字段
- coverage instruction/line covered 与 missed 计数
- TestDrive、环境变量、模块状态和真实子进程清理

### 并行分组

- 完整诊断 PoC 使用已验证的 `Run.ParallelThrottleLimit=2`，避免入口默认落到尚未正式对照的自动值；自动、2、4 三档性能比较转入后续优化任务。
- 默认允许纯模块和隔离 fixture 文件并行。
- 修改全局环境变量、固定端口、共享报告路径、进程注册表或宿主模块状态的文件使用 `#pester:no-parallel`。
- 报告、coverage 和临时目录继续使用唯一运行级路径；不在多个外层 Pester 进程间共享默认文件。

### PoC 门禁

只有以下条件全部满足才将默认 full 切换到 Pester 6 并行：

- 串行与并行失败集合一致，无新增随机失败。
- assertions NUnit 可解析，串行与并行失败集合一致，无新增随机失败。
- NUnit reporter 可正常解析。
- 中断后没有残留 Pester、fixture 或安装叶子进程。
- CodeCoverage 开启时拒绝并行请求，避免 Pester 6 静默退回串行后产生虚假样本。

Pester 6.0.1 官方实现会在 CodeCoverage 开启时退回串行，因此当前任务不再提升默认 full 为内置并行。coverage `<=240s` 目标转入 `.trellis/tasks/08-12-design-pwsh-coverage-sharding`，由外层独立进程分片与报告合并设计承接。

## 测量设计

- 所有正式样本通过 duration reporter 分配唯一 NUnit3/JSON artifact。
- coverage 正式样本按 Pester 版本分别运行三轮；assertions 并行 PoC 单独记录，不与 coverage 样本计算中位数。
- 记录 PowerShell/Pester 版本、并行状态、CPU 逻辑核数、Discovery/Run/coverage 阶段和 Top 文件。
- 性能运行期间禁止其他 Pester、QA 或安装进程并发。

## 风险与回滚

- Pester 6 并行是实验能力：保留串行默认直到提升门禁完成，并保留 5.7.1 入口。
- 文件可能隐式共享环境：先从保守 `#pester:no-parallel` 集合开始，再用证据逐步放开。
- coverage tracer 可能漂移：继续使用 breakpoint coverage；不启用已证明少采的 profiler tracer。
- CI/Docker 版本漂移：所有安装入口固定版本，升级通过单一版本常量完成。
- 若 Pester 6 PoC 失败，阶段一成果仍可独立交付；外层分片另建任务，不在本任务临时扩张。
