# 实施计划

## 1. 固化版本与基线

- 记录当前 Pester 5.7.1 串行 Top 文件和三轮 coverage-on 基线。
- 新增统一 Pester 版本来源，固定本机安装入口、Docker 和 CI。
- 为显式版本导入、缺失版本和不支持并行的错误路径补测试。

## 2. 优化 install.Tests 串行热点

- 定位并 Mock 真实 `Install-Module`、仓库查询和模块发现边界。
- 恢复/保留安装调用顺序、次数、失败后继续和无自动重试合同。
- 运行单文件冷/热 benchmark，目标典型耗时不超过 15 秒。

## 3. 优化剩余串行热点

- 收缩 Windows/Linux 重复入口进程，保留真实参数、JSON 和退出码 smoke。
- 优化 `PackageSources.Tests.ps1` 的事务 fixture、导入和文件系统初始化。
- 检查 docker/install/moduleContract/documentation 的重复扫描与导入。
- 每处理一个热点后运行对应窄测和 duration benchmark。

## 4. 阶段一验收

- 运行 `pnpm qa` 和受影响 PowerShell 窄测。
- 运行 Windows host Pester 5.7.1 coverage-on 三轮。
- 门禁：中位数 `<=290s`、最慢值 `<=330s`、coverage `>=50%`，无新增失败。
- 未达到门禁时继续处理最新 Top N，不提前进入并行阶段。

## 5. Pester 6.0.1 串行兼容

- 安装/导入 Pester 6.0.1，与 5.7.1 保持可切换。
- 串行运行配置测试、热点窄测、QA 和 full。
- 比较 discovery、失败集合、NUnit、coverage、Mock/TestDrive 生命周期和清理结果。
- 修复迁移差异，禁止通过删除测试或降低 coverage 解决兼容问题。

## 6. Pester 6 文件级并行 PoC

- 增加显式并行开关，只在 Pester 6 上设置受支持的 `Run.Parallel`。
- 增加可选 throttle 配置，完整诊断 PoC 固定使用已验证的 2；自动、2、4 三档正式性能采样转入后续优化任务。
- 审计共享状态测试并添加 `#pester:no-parallel`。
- 验证唯一报告路径、TestDrive、环境变量、模块和进程隔离。
- 运行 assertions 并行样本，先解决随机失败再运行 coverage。

## 7. 阶段二 PoC 验收与范围校正

- 运行 Pester 6 assertions 文件级并行完整 PoC，验证 NUnit、失败集合、`#pester:no-parallel` 和清理合同。
- 明确拒绝 `coverage + parallel`；默认 `test:pwsh:full` 保持串行，保留 Pester 5 回退入口。
- 创建外层 coverage 分片后续任务，承接 `<=240s`、JaCoCo/NUnit 合并和 throttle/负载均衡实验。
- Docker 可用时运行 `pnpm test:pwsh:all`；不可用时验证快速失败并注明 Linux 覆盖依赖 CI/WSL。

## 8. 最终检查

- 执行 `pnpm qa`、Vitest runner/reporter 测试、`git diff --check` 和 PowerShell 格式检查。
- 派发独立 `trellis-check`，重点审查并行隔离、coverage 等价和回退入口。
- 更新 Pester 性能规范与任务研究数据后提交。

## 回滚点

- 阶段一热点优化独立于 Pester 升级，可单独保留。
- Pester 6 串行兼容、并行开关和默认入口提升分别形成独立逻辑提交候选。
- 任一并行合同不满足时，默认入口保持 serial，不删除回退脚本或旧版本支持。
