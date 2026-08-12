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

- Pester 6.1.0 原生并行 coverage 已在 2026-08-12 完成仓库级 throttle 2 对照，但未通过门禁：串行 `360.207s`、instruction `3011/1860`（61.81%），并行 `634.090s`、instruction `3030/1841`（62.20%）；NUnit 测试集合等价，coverage 计数不等价且并行显著更慢。
- 因首个固定候选同时失败正确性与 `<=270s` 性能门禁，自动与 throttle 4 采样按短路规则不再执行；默认 `test:pwsh:full` 继续串行，本任务恢复为外层进程分片备用设计。
- 仓库新增 `test:pwsh:coverage:parallel:poc` 薄入口仅用于保留可复现诊断，不得作为默认 full。
- Pester 5.7.1 与 6.x 的 coverage instruction 计数可能存在差异，任何原生或外层并行方案都必须与同版本串行基线验证计数等价，不能只比较百分比。

## Out of Scope

- 修复既有 WSL guest Windows 路径失败。
- 降低 coverage 门槛或删除真实入口测试换取性能数字。
- 在设计和 PoC 未通过前切换默认 full。
