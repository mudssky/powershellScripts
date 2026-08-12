# 修复 GitHub Actions Pester Test 失败

## Goal

修复 GitHub Actions `Pester Test` 在 Windows、Ubuntu 与 macOS runner 上无法非交互安装仓库固定 Pester 版本的问题，使测试矩阵能够进入实际 Pester 执行阶段。

## Background

- 失败运行：GitHub Actions run `31598938891`，提交 `594c592344e0a39bdc8d7cc0ffaf596552c1a418`，时间 `2026-08-12T12:56:59Z`。
- 三个平台都在 `.github/workflows/test.yml` 的 `Install pinned Pester` 步骤失败，尚未执行 Pester 测试。
- Ubuntu 与 macOS 日志明确显示 PSGallery 为 untrusted repository，并尝试请求交互确认；CI 无输入后 `Install-PSResource` 抛出 `Object reference not set to an instance of an object.`。Windows 同一安装调用也产生相同异常。
- 本机 `Microsoft.PowerShell.PSResourceGet 1.2.0` 的 `Install-PSResource` 支持调用级 `-TrustRepository`，适用于非交互 CI；无需永久修改全局 repository 配置。

## Requirements

- R1：`scripts/pwsh/devops/Install-Pester.ps1` 安装缺失的固定 Pester 版本时，必须显式允许本次 PSGallery 安装在未预置信任的 runner 上非交互执行。
- R2：已安装精确版本时继续保持幂等，不调用 `Install-PSResource`。
- R3：继续从 `.pester-version` 读取默认版本，保留 `-Version`、`-Scope` 和 terminating error 合同，不重新引入 `Install-Module`、浮动 latest 或无条件 `-Reinstall`。
- R4：信任仅限当前安装调用；不得使用 `Set-PSResourceRepository` 永久修改用户或 runner 的 PSGallery 状态。
- R5：测试必须锁定 `-TrustRepository` 参数，并证明现有精确版本、Scope、ErrorAction 与无 Reinstall 合同不变。
- R6：`Publish Test Report` 仅在 `tests/reports/testResults.xml` 实际存在时运行；正常 Pester 测试失败但已生成 XML 时仍必须发布，前置安装失败或测试未启动时不得制造第二个 reporter 失败。

## Acceptance Criteria

- [x] 安装脚本定向 Pester 测试证明缺失版本时恰好一次调用 `Install-PSResource`，参数包含 `-Name Pester -Version 6.1.0 -Scope <scope> -TrustRepository -ErrorAction Stop`，且不含 `-Reinstall`。
- [x] 已安装精确版本的幂等测试仍证明安装调用次数为 0。
- [x] 本地 `pwsh -NonInteractive` smoke 证明调用级 `-TrustRepository -WhatIf` 不触发 repository trust prompt、不执行安装，且 PSGallery `Trusted=false` 前后不变。
- [x] `tests/InvokePesterMode.Tests.ps1`、PowerShell QA 与串行 full coverage 通过；`test:pwsh:all` 因 Docker CLI 不可用按合同安全短路，Linux 覆盖依赖本次 GitHub Actions。
- [ ] workflow YAML 保持三平台矩阵与固定 Pester 版本来源；报告步骤使用“始终评估且仅在 XML 存在时运行”的条件。修复后重新触发或推送的 GitHub Actions run 中三个 `Install pinned Pester` 步骤通过并进入 `Run Pester`，且缺失报告不会产生第二个失败。

## Out of Scope

- 更换 PSGallery、修改组织级 GitHub runner 镜像或永久信任仓库。
- 修改 Pester 6.1.0 固定版本、coverage 策略或重新启用原生并行 coverage。
- 处理与本次安装失败无关的 Node/Vitest 或其他 workflow 问题。
