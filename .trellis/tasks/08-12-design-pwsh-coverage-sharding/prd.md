# 设计 PowerShell coverage 外层分片与报告合并

## Goal

设计独立 Pester 进程分片、JaCoCo/NUnit 合并、环境隔离、负载均衡与三轮 coverage 门禁，不降低现有覆盖率和真实入口合同。

## Requirements

- 设计仓库级外层 runner，将测试文件分配到多个独立 `pwsh -NoProfile` 进程；不依赖 Pester 6 内置 `Run.Parallel` coverage 支持。
- 每个 lane 使用唯一 NUnit、JaCoCo、duration JSON、临时目录和环境变量作用域，支持中断时清理完整进程树。
- 定义可验证的 JaCoCo 合并规则，避免重复 instruction、路径漂移或 covered/missed 计数失真；合并前后需与同 commit 串行 coverage 基线对照。
- 定义 NUnit 聚合、退出码聚合、Skip/NotRun/失败集合和 lane 崩溃处理合同。
- 基于历史 duration artifact 做负载均衡，并对 lane 数、冷启动成本、磁盘/Defender 竞争进行 A/B 测量。
- 保留真实 UTF-8、多流、Running、退出码、中断清理和平台入口合同，不降低 50% coverage 门槛，不扩大 coverage 排除范围。
- 先完成设计与小规模 PoC；未经用户确认，不切换默认 `test:pwsh:full`，不自动实现完整分片方案。

## Acceptance Criteria

- [ ] `design.md` 明确 lane 划分、串行文件集合、唯一 artifact、进程清理和回滚设计。
- [ ] 选定并验证 JaCoCo 与 NUnit 合并工具/算法，给出相同 commit 的计数等价判定方法。
- [ ] 小规模至少两个 lane 的 PoC 证明测试不会漏跑、重复计数或互相覆盖报告。
- [ ] 三轮 Windows host coverage-on 样本报告平均值、中位数、最慢值、coverage、失败集合和 Top lane/file。
- [ ] 目标保持中位数 `<=240s`、最慢值 `<=270s`、coverage `>=50%`；未达到时保留串行默认并记录瓶颈。
- [ ] Docker 不可用时明确 Linux coverage 依赖 CI/WSL，不把未验证平台写成已支持。

## Background

- Pester 6.0.1 在 CodeCoverage 开启时会强制退回串行，内置文件级并行无法承接 coverage 性能目标。
- 使用实验性 WSL 串行标记时，assertions 并行 PoC throttle 2 可生成完整 NUnit，Run 196.65 秒，仅保留既有 WSL guest Windows 路径失败；该标记因 changed QA 合同未保留，后续设计需解决串行文件分类与既有失败隔离。
- Pester 5.7.1 与 6.0.1 的单文件 coverage instruction 计数存在差异，合并方案必须验证语义等价，不能只比较百分比。

## Out of Scope

- 修复既有 WSL guest Windows 路径失败。
- 降低 coverage 门槛或删除真实入口测试换取性能数字。
- 在设计和 PoC 未通过前切换默认 full。
