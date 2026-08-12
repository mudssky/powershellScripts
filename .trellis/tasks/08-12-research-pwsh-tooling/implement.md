# 实施计划

## 1. PSResourceGet 安装边界

- 扩展 `psutils/modules/install.psm1` 的安装包装函数，改用 `Install-PSResource` 并支持 Scope、精确 Version 与显式 Reinstall。
- 保持 `Install-RequiredModule` 的公共签名、ShouldProcess、逐项结果、安装后导入和失败继续合同。
- 更新 `psutils/tests/install.Tests.ps1`，测试 PSResourceGet 参数映射、WhatIf、成功导入和失败继续。
- 将 `scripts/pwsh/devops/Install-Pester.ps1` 改为独立 PSResourceGet bootstrap，精确读取 `.pester-version`。
- 清理活动代码中的其他 `Install-Module` 调用：misc Pester 入口转发规范安装脚本，pslint 与 Start-PSReadline 复用新边界。
- 运行安装相关窄测和各平台 `installModules.ps1 -WhatIf` smoke。

## 2. Pester 6.1.0 固定版本

- 将 `.pester-version` 更新为 `6.1.0`。
- 更新配置、测试与规范中只描述当前默认版本的 6.0.1 文案；保留历史研究数据中的原始版本事实。
- 通过 `pnpm pester:install` 安装精确 6.1.0，确认 runner 实际导入该版本。
- 验证 Dockerfile 和 CI 仍只读取 `.pester-version`，不复制版本常量。
- 验证 duration artifact 的 `pesterVersion` 为 6.1.0，显式 5.7.1 回退仍记录 5.7.1。

## 3. 串行兼容

- 更新 `PesterConfiguration.ps1` 的并行能力判断，移除 6.0.1 专属的 coverage 拒绝规则。
- 更新 `tests/PesterConfiguration.Tests.ps1` 与 `tests/InvokePesterMode.Tests.ps1`：6.1.0 接受 coverage + parallel，5.7.1/不支持版本仍明确失败。
- 运行配置、runner、install 及历史热点窄测。
- 运行 `pnpm test:pwsh:qa`、`pnpm test:pwsh:full:assertions`、`pnpm test:pwsh:full:serial`。
- 比较测试数、失败集合、NUnit 和 JaCoCo；修复兼容差异，不删除测试或放宽 coverage。

## 4. 原生并行 coverage PoC

- 为 coverage 输出增加单次运行唯一路径覆盖能力，保持默认 `tests/reports/coverage.xml` 合同不变。
- 新增 `test:pwsh:coverage:parallel:poc` 薄入口，复用 `Invoke-PesterMode.ps1`，不复制环境变量拼装。
- 对共享宿主状态文件复核 `#pester:no-parallel`，只按真实隔离证据调整。
- 分别运行 throttle 0、2、4 的正确性样本，生成唯一 NUnit、JaCoCo 和 duration JSON。
- 自动比较串行/并行 test-case 集合、失败集合和 JaCoCo instruction/line 计数。
- 任一档正确性不等价时先修复或判定原生方案失败，不进入正式性能采样。

## 5. 三轮性能门禁与默认入口决策

- 对通过正确性门禁的每个 throttle 连续运行三轮，期间不并发其他 Pester/QA。
- 汇总平均值、中位数、最慢值、coverage、Top 文件和失败集合。
- 门禁：中位数 `<=240s`、最慢值 `<=270s`、coverage `>=50%`、计数等价、无新增失败或残留进程。
- 通过：选择最稳健 throttle，将 `test:pwsh:full` 指向原生并行 coverage，永久保留 serial 与 Pester 5 回退入口。
- 未通过：保持串行默认，记录阻塞证据，继续外层 coverage 分片任务。

## 6. 最终验证与收束

- 执行 `pnpm qa`。
- 执行 `pnpm test:pwsh:all`；Docker 不可用时执行 `pnpm test:pwsh:full` 并记录 Linux 覆盖依赖 CI/WSL。
- 涉及 coverage 规范，额外执行 `pnpm test:pwsh:coverage`。
- 更新 `.trellis/spec/pwsh-scripts/package/pester-performance.md`、必要安装规范和当前 coverage 分片任务状态。
- 派发 `trellis-check` 复核安装语义、版本单一来源、并行隔离、报告等价和回滚入口。

## 回滚点

- PSResourceGet 迁移独立回滚，不依赖 Pester 默认入口提升。
- Pester 版本升级、原生并行开关和默认入口切换分开验收。
- 原生并行任一门禁失败时，只回退默认入口到 serial，不删除 6.1.0 串行兼容成果。
