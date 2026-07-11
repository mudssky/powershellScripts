# 技术设计：PackageSources 测试隔离与性能优化

## 1. 问题边界

`tests/PackageSources.Tests.ps1` 当前用 27 次 `Invoke-PackageSourceCli` 启动独立 PowerShell 进程。事务场景又通过 fake chsrc/npm `.ps1` 产生额外 PowerShell 子进程，导致单文件稳定耗时约 39.48 秒。

优化不改变 package source 生产合同，只重构测试层级与 fixture：

1. 少量 CLI 集成测试验证 `Switch-Mirrors.ps1` 的参数解析、JSON/退出码和兼容映射。
2. 事务、状态、drift、Ensure、Auto 与 adapter 行为在当前 Pester 进程直接调用 `Invoke-PackageSourceAction`。
3. 外部 chsrc/npm fixture 使用低启动成本原生命令脚本。
4. 默认网络边界失败，具体网络策略用例显式覆盖 Mock。

## 2. 测试层级

### 2.1 CLI 集成层

保留约 4 条真实 `pwsh -File Switch-Mirrors.ps1` 用例：

- Direct + JSON 文档和退出码。
- 缺少 Target 的结构化参数错误。
- Apply `-WhatIf` 到 Plan 的映射。
- legacy Docker `-WhatIf` 到 DryRun 的兼容输出。

这些用例不执行 Apply、网络探活或外部 adapter，因此子进程不接触真实网络和用户配置。

### 2.2 领域行为层

其余用例直接调用模块导出的 `Invoke-PackageSourceAction`。测试 helper 负责：

- 临时覆盖 `HOME`、XDG 路径、状态根目录及 adapter 可执行路径。
- 捕获结构化返回对象或异常中的 `ExitCode`/`Code`。
- 在 `AfterEach` 恢复进程环境，避免 Pester runspace 污染。

测试继续保留文件 snapshot、manifest、drift、orphan、rollback 和 token 不泄露的真实临时文件行为；不把领域逻辑全部 Mock 掉。

## 3. 低成本 fixture

### Unix

- fake chsrc/npm 使用带 shebang 的 `.sh` 文件并赋执行权限。
- 参数解析只实现测试所需命令；输出和文件写入保持现有 fixture 语义。
- 临时目录仍位于 `$TestDrive`，测试结束由 Pester 统一清理。

### Windows

- 对 Windows 会执行的 fixture 使用 `.cmd`；Unix-only managed-env/system adapter 用例继续保留现有平台 Skip。
- fixture 选择集中在一个 helper，不在每个用例复制平台分支。

生产 `AdapterSupport.psm1` 不增加测试专用分支；它继续把 override 当普通可执行文件处理。

## 4. 网络隔离

进程内测试默认安装以下失败保护：

- `PackageSources` 模块内 `Invoke-WebRequest` 默认 Mock 为抛出“未声明网络访问”。
- `DockerAdapter` 模块采用同样保护。
- Auto/镜像探活用例在所属 Context 内覆盖明确的成功、失败或序列响应，并用 `Should -Invoke` 验证次数与 URI。

CLI 集成层只运行不会进入网络分支的 Plan/参数场景。这样任何新增真实网络调用都会直接使测试失败，而不是依赖开发机是否联网。

## 5. Benchmark

新增 `tests/benchmarks/PackageSourcesTest.Benchmark.ps1`：

- 默认运行 `tests/PackageSources.Tests.ps1` 3 次，每次使用新的 `pwsh -NoProfile` 子进程。
- 输出平台、PowerShell 版本、样本、平均值、中位数、最小值和最大值。
- 支持 `-Iterations`、`-TestPath`、`-OutputPath` 与 `-AsJson`。
- 采样时关闭多余 Pester 输出，只测单文件完整执行。

`tests/Invoke-Benchmark.Tests.ps1` 使用 `$TestDrive` 中的微型 Pester fixture 和单次迭代验证 benchmark 可发现、可执行且 JSON 可解析，不运行真实 PackageSources 性能门槛。

本次验收在同一 macOS 环境手动执行 3 次，目标中位数不高于 20 秒且相对 39.48 秒提升至少 45%。CI 不写死绝对耗时。

## 6. `Removed ... files` 输出

macOS QA 与 PackageSources 单文件基线日志均未复现该输出；本地 `Remove-Item` 最小实验也未复现。实施阶段使用现有 duration/log harness 捕获 full host 与 Linux 容器输出：

- 若来源属于 PackageSources fixture 或其子进程，则在本任务修复。
- 若来源属于 coverage、Docker 或其他测试文件，则记录日志锚点和独立后续范围，不做全局静默重定向。

## 7. 兼容与回滚

- 不修改 package source 公共 API、catalog schema 或事务文件格式。
- 若进程内改造暴露 runspace 污染，优先修复环境恢复 helper；不能退回 27 条子进程测试作为长期方案。
- 保留少量 CLI 集成层作为接口回归安全网。
