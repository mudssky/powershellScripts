# Pester 全量测试性能合同

## 1. Scope / Trigger

- 适用于修改 `PesterConfiguration.ps1`、`tests/**/*.Tests.ps1`、`psutils/tests/**/*.Tests.ps1`、PowerShell 测试 runner 或耗时报告器。
- 当测试通过减少真实子进程、模块导入或命令发现来提速时，必须同时保留入口、进程和输出合同，不能只验证内部返回值。

## 2. Signatures

```powershell
pnpm test:pwsh:full
pnpm test:pwsh:full:serial
pnpm test:pwsh:full:pester5
pnpm test:pwsh:coverage:parallel:poc
pnpm test:pwsh:coverage:slowest
pnpm test:pwsh:all
```

```text
node scripts/pester-duration-report.mjs \
  --command "<command>" \
  [--nunit <xml>] [--coverage <xml>] [--json <json>] [--lane <name>] [--top <count>]
```

## 3. Contracts

- `PESTER_RESULT_PATH`：可选 NUnit3 输出路径；并发或连续采样必须使用唯一文件名。
- `PESTER_COVERAGE_PATH`：可选 JaCoCo 输出路径；并发或连续 coverage 采样必须使用唯一文件名。
- `PWSH_TEST_MODE`：选择 `qa` / `full` 等测试路径集合。
- `PWSH_TEST_ENABLE_COVERAGE`：显式控制 coverage；`full` 验收保持开启。
- duration JSON 必须包含 `schemaVersion`、`command`、`lane`、`startedAt`、`endedAt`、`elapsedMs`、`exitCode`、`phases`、`nunitPath`、`coveragePath`、`files` 和 `testCases`。
- `test:pwsh:all` 必须在启动 host lane 前检查 Docker CLI、daemon 和 Compose；缺失时输出 `pnpm test:pwsh:full` fallback，不启动长测试。

## 4. Validation & Error Matrix

| 条件 | 预期行为 |
|---|---|
| 未提供 `--file` 或 `--command` | reporter 返回 1 并输出 usage |
| 被测命令失败 | reporter 仍写 JSON artifact，并透传退出码 |
| NUnit 文件不存在 | 保留控制台阶段数据，文件和用例列表可为空 |
| Docker CLI/daemon/Compose 不可用 | `test:pwsh:all` 快速失败，不启动 host/linux lane |
| coverage 低于 50% | full coverage 门禁失败 |
| 完整命令 fixture 缺字段 | 测试应显式失败，不回退真实 `Get-Command` 扫描 |
| 命令显式指定 `-PesterVersion` | artifact 的 `pesterVersion` 与该参数一致 |
| pnpm 等间接入口未显式指定版本 | 依次使用 `PWSH_PESTER_VERSION`、`.pester-version`；两者都不存在时才探测已安装版本 |

## 5. Good / Base / Bad Cases

- Good：状态机测试 Mock 私有进程边界，同时保留 UTF-8、多流、`[Running]`、中断清理和入口 JSON/exit 的真实进程用例。
- Base：单个入口 smoke 验证参数解析、单文档 JSON 和退出码，清单选择在模块内直接测试。
- Bad：每个 `It` 都启动新 `pwsh`，或不完整 fixture 静默触发真实命令自动发现。

## 6. Tests Required

- reporter：ANSI 日志、阶段耗时、NUnit3 文件/用例 Top N、lane、失败退出码、无 NUnit artifact。
- all runner：Docker CLI、daemon、Compose 三类预检失败，以及成功时 host/linux lane 启动顺序。
- Windows 命令发现：present/missing、PATH 变化、Scoop cmd shim、WinGet module export、完整 `CommandAvailability`。
- 编排器：状态机调用顺序与次数；真实 UTF-8、多流、Running、中断进程树清理。
- 性能验收：Windows host coverage-on 连续 3 轮，报告中位数、最慢值和 coverage；样本期间不得并发运行其他 Pester。

## 7. Wrong vs Correct

### Wrong

```powershell
# 每个分类用例都因缺字段回退到昂贵的真实环境扫描。
Get-WindowsInstallEnvironment -CommandAvailability @{ winget = $true }
```

### Correct

```powershell
# fixture 覆盖模块要求的全部命令能力，纯分类测试不访问宿主环境。
Get-WindowsInstallEnvironment -CommandAvailability $completeCommandAvailability
```

## Design Decisions

- 复用 `psutils/modules/commandDiscovery.psm1` 的 `Find-ExecutableCommand` 探测 PATH/PATHEXT 外部命令，不新增同类 helper。
- WinGet PowerShell cmdlet 不属于 PATH 命令，使用一次模块导出能力快照。
- Pester 5.7.1 的 `Run` 配置没有 `Parallel` 属性；请求并行时必须明确拒绝，不能静默退回串行。
- Pester 6.1.0 支持文件级 `Run.Parallel` 与 CodeCoverage 合并；旧于 6.1.0 的版本请求 parallel coverage 时仍必须明确拒绝。
- `test:pwsh:full:parallel:poc` 是 assertions 诊断入口，固定 throttle 2；`test:pwsh:coverage:parallel:poc` 是原生并行 coverage 的薄 PoC 入口，同样固定 throttle 2 并由 reporter 分配唯一 NUnit、JaCoCo 与 duration artifact。
- 默认 `test:pwsh:full` 保持串行 coverage。2026-08-12 的同提交对照中，串行基线为 `360.207s`、instruction `3011/1860`（61.81%），原生并行 throttle 2 为 `634.090s`、instruction `3030/1841`（62.20%）；两者 NUnit 都是 `965 total / 939 passed / 0 failed / 26 skipped`，但 coverage 计数不等价且并行超过 `270s` 最慢值门禁。
- 原生并行候选一旦在首个固定 throttle 上失败测试集合、coverage 计数或性能门禁，后续 throttle 档位允许短路，不得用更多采样掩盖已失败的正确性合同；此时恢复外层进程分片任务作为备用方案。
- 调用真实 Bash/WSL、修改进程环境或依赖共享宿主状态的测试必须显式隔离。Windows 调用 WSL guest 脚本时，应先把 Windows 路径规范为正斜杠并通过 `wsl.exe -- wslpath -a` 转换，再用 `wsl.exe -- env ... bash` 显式传递测试环境；不能混用 Git Bash `cygpath` 与 WSL `bash.exe`。
- 统一 runner 在同进程被调用时，结束后必须恢复调用方原有测试环境变量；调用前没有加载 Pester 时不得留下目标版本模块。若当前进程已加载不同 Pester 版本，必须明确拒绝并要求独立 `pwsh`，不能尝试卸载后切换或恢复跨版本 DLL。
