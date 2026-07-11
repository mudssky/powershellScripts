# 实施计划：PackageSources 测试隔离与性能优化

## 阶段 A：基线与测试合同

- [x] 记录 macOS、PowerShell 版本、PackageSources 三次基线和 QA 慢文件报告。
- [x] 统计现有 CLI 子进程与 fake `.ps1` 子进程数量，建立改造前调用边界。
- [x] 保留参数解析、JSON/退出码、WhatIf 和 legacy Docker 四类 CLI 集成测试。

## 阶段 B：进程内领域测试

- [x] 新增测试 helper，直接调用 `Invoke-PackageSourceAction` 并隔离/恢复环境变量。
- [x] 将 Apply/Restore/Status/Ensure、drift、lock、orphan、Auto 和 adapter 测试迁到进程内。
- [x] 保持真实临时文件、manifest 和 snapshot 断言，不弱化事务覆盖。
- [x] 默认 Mock PackageSources/DockerAdapter 网络边界为失败；具体 Context 显式覆盖并验证调用。

## 阶段 C：低成本外部命令 fixture

- [x] Unix 使用可执行 shell fake chsrc/npm；Windows 保留 PowerShell fixture。
- [x] 保持版本、参数日志、brew/npm/ubuntu 修改语义与当前测试一致。
- [x] 确认测试不调用真实 chsrc、npm、系统包管理器或公网。

## 阶段 D：性能 benchmark

- [x] 新增 `tests/benchmarks/PackageSourcesTest.Benchmark.ps1`，支持 3 次默认采样和 JSON/文件输出。
- [x] 在 `tests/Invoke-Benchmark.Tests.ps1` 增加 discovery 与微型 fixture 执行契约。
- [x] benchmark 采样过程保持安静，不把 JSON 转换和报告写入计入目标测试耗时。

## 阶段 E：输出来源追踪

- [x] 捕获 full host 与 Linux 容器日志并搜索 `Removed ... files`。
- [x] 该文案是 PowerShell 7.5 在交互终端为 `Remove-Item` 渲染的进度记录，重定向日志时不会保留。统一 Pester 配置只为 `Remove-Item:ProgressAction` 设置 `SilentlyContinue`。
- [x] 未使用全局 `$ProgressPreference` 或 stdout 丢弃掩盖未知副作用。

## 阶段 F：验证

- [x] 单文件回归：macOS `24/24`，Linux 容器 `24/24`。
- [x] 3 次采样：`6014.705 / 6043.982 / 6109.053 ms`，平均 `6055.913 ms`，中位数/最慢 `6109.053 ms`，相对 `39.48s` 基线提升约 `84.5%`。
- [x] `pnpm benchmark -- package-sources-test -Iterations 3 -AsJson` 输出可解析。
- [x] `pnpm qa`。
- [x] `pnpm test:pwsh:all`：host `762 passed / 0 failed`，Linux `759 passed / 0 failed`。
- [x] `git diff --check`，确认 `.zcode/` 为无关未跟踪目录，本任务未修改。

## 风险与回滚点

- Pester 模块 Mock 和环境变量是进程级状态，必须在每个用例后恢复；任一泄漏会导致顺序相关失败。
- CLI 集成用例数量减少后，必须保持公共参数/输出合同覆盖，不能只测领域函数。
- benchmark 只报告数据，不在 CI 使用绝对时间失败门槛。
