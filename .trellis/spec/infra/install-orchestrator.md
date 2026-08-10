# 统一安装编排器规范

> 本规范记录根 `install.ps1`、`config/install/steps.psd1` 与 `InstallOrchestrator.psm1` 的兼容和执行合同。

## Scenario: 跨平台 Stage 1 安装编排

### 1. Scope / Trigger

- Trigger: 修改根 `install.ps1` 的 Preset/步骤参数、`config/install/**`、`scripts/pwsh/install/**` 或对应 Pester 测试。
- Scope: Stage 1 步骤选择、平台入口解析、依赖传播、子进程隔离、source cleanup、Text/JSON 汇总与重跑命令。
- Design intent: 根编排器只拥有步骤图和运行状态；平台叶子拥有安装业务，Stage 0 拥有 Git、包管理器和 PowerShell 7 bootstrap。

### 2. Signatures

```powershell
./install.ps1
./install.ps1 -installApp
./install.ps1 -ListSteps [-OutputFormat Text|Json]
./install.ps1 -Preset Core|Full `
  [-Step <id[]> | -FromStep <id>] [-SkipStep <id[]>] `
  [-NetworkMode Direct|China|Auto] [-OutputFormat Text|Json] `
  [-Unattended | -NonInteractive] [-WhatIf]
```

```bash
pnpm provision:list
pnpm provision:core:preview
pnpm provision:full:preview
pnpm provision:core [-NetworkMode China | -Step <id> | -FromStep <id>]
pnpm provision:full [-NetworkMode China | -Step <id> | -FromStep <id>]
```

- 无参数调用保持仓库工具准备行为；不得隐式转为装机。
- `-installApp` 仅为弃用兼容入口，不等价于 Full，也不能与编排参数组合；Linux 分支只转发到新的 Core CLI 叶子。
- Stage 0 获得 Git、平台包管理器和 PowerShell 7；根 Stage 1 从 `03 sources` 开始。
- `Core` 选择 `03`～`07` 与 `99`；`Full` 追加 `08`～`11`。
- `-Step` 精准执行且不展开依赖；`-FromStep` 假定前序已完成；`-SkipStep` 排除依赖时阻断下游。
- 根 package scripts 只提供 `provision:*` 薄别名；不得使用与 pnpm 内置 `install` 命令冲突的 `install:*`。脚本依赖 Node.js、pnpm 与 PowerShell 7，只属于 Stage 1，参数直接写在脚本名后，不增加会原样传给 PowerShell 的 `--`。

### 3. Contracts

- `config/install/steps.psd1` 是编号、Preset、依赖和平台未来路径的唯一真源，只允许 data literal。
- 非 source 叶子默认只接收 Preset 与交互参数；Windows `platform-automation` 额外接收 NetworkMode，以便独立 09 调用遵守 winget Stage 0 source 合同。
- validator 必须拒绝重复 ID/编号、未知依赖、循环、未知 Runner、非法顺序和 Supported 但缺少 Path。
- 步骤稳定串行执行；禁止 `Invoke-Expression` 或拼接命令行，必须使用 `ProcessStartInfo.ArgumentList`。
- `Supported=false` 为 `Skipped`；入口缺失、依赖失败/跳过或叶子退出 10 为 `Blocked`；其他非零退出为 `Failed`。
- 独立步骤与 `verify` 尽可能继续。整体优先级为 Failed > Blocked > Succeeded；退出码依次为 1、10、0，参数错误为 2。

#### Source Lifecycle And Output

- Direct 不创建事务；China 保留事务并输出 Restore 命令；Auto 只要获得事务 ID，就必须在 `finally` 中调用共享 `Switch-Mirrors.ps1 -Action Restore`。
- Auto Restore 失败使成功运行提升为 Blocked；已有 Failed 时不得覆盖原始失败，清理状态单独写入 `SourceRestore`。
- `-WhatIf` 不创建事务或执行 Restore 写操作。
- JSON stdout 必须只有一个 document；叶子 stdout/stderr 由编排器捕获，稳定结果只保存截断且脱敏的摘要。
- 失败汇总必须提供包含 Preset、步骤、NetworkMode 和交互模式的 `-Step` 重跑命令，以及 `-FromStep` 继续命令。
- Text 汇总通过 `[Console]::Out.WriteLine` 输出时，包含多个 `-f` 参数的完整格式表达式必须用括号规约为单个方法参数；不得依赖 PowerShell 在方法调用逗号与格式参数逗号之间猜测绑定。
- Text 模式必须为每个实际启动的叶子即时向 stderr 输出 `[Running] <number> <id>: <safe-command>`；持续运行时每 15 秒输出 `[Running] <number> <id> elapsed=<seconds>s`。命令只能来自 `Format-InstallCommand`，不得转发任意叶子 stdout/stderr。
- JSON 模式必须关闭运行进度；stdout 继续只有最终单个 JSON document，stderr 也不得出现 Text 进度行。
- 叶子等待必须使用有限轮询以响应中断，但不得把轮询或 heartbeat 解释为安装超时；等待异常或中断时必须终止仍存活的直接子进程树，再释放 `Process`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| Step/FromStep/SkipStep/NetworkMode/WhatIf 未搭配 Preset | 参数错误，退出 2，且不执行 legacy 副作用 |
| Step 与 FromStep 同时使用 | 参数错误，退出 2 |
| Unattended 与 NonInteractive 同时使用 | 参数错误，退出 2 |
| ListSteps 携带执行参数，或 OutputFormat 单独使用 | 参数错误，退出 2 |
| 步骤 ID 不存在或不属于 Preset | 参数错误，退出 2 |
| 平台 Supported=false | 步骤为 Skipped，不视为失败 |
| Supported=true 但入口文件缺失 | 步骤为 Blocked，整体至少退出 10 |
| 依赖步骤 Failed/Blocked/被 SkipStep 排除 | 下游为 Blocked；独立步骤继续 |
| 叶子退出 1/2/未知非零 | 步骤为 Failed，整体退出 1 |
| 叶子退出 10 | 步骤为 Blocked；若无 Failed，整体退出 10 |
| Auto 已获得事务 ID | 无论后续成功、失败或异常，都在 finally 尝试 Restore |
| Auto Restore 失败且安装步骤已 Failed | 整体仍为 Failed/1，SourceRestore 单独为 Blocked |
| JSON 模式叶子输出日志 | 日志被捕获到结果摘要，stdout 仍只有一个 JSON document |
| `pnpm provision:* -- -NetworkMode China` | 字面量 `--` 会传给 PowerShell 并触发参数错误；必须直接追加 `-NetworkMode China` |
| Text 汇总把多参数 `-f` 表达式直接写进 `WriteLine(...)` | PowerShell 把逗号解释为方法参数边界并抛格式化异常 |
| Text 模式叶子持续运行超过 15 秒 | 启动时立即写安全命令到 stderr，之后每 15 秒写 elapsed heartbeat；最终汇总和结果不变 |
| JSON 模式执行同一叶子 | 不输出任何 Text 进度，stdout 仍可作为单个 JSON document 解析 |
| 等待叶子时发生中断或异常 | 终止仍存活的直接子进程及其后代，不遗留下载或安装进程 |

### 5. Good/Base/Bad Cases

- Good: 平台任务只新增注册表声明对应的薄叶子，根编排器无需复制 Homebrew、apt、winget 或 profile 业务。
- Good: Auto source 步骤失败但返回事务 ID 时，仍在 finally 恢复已修改资源。
- Base: Direct 模式仍执行 `03 sources` 的结构化 no-op，以便汇总保持相同步骤模型，但不创建事务。
- Bad: 叶子缺失时调用旧编号脚本并把运行标为成功。
- Bad: JSON 模式让叶子日志直通 stdout，或 cleanup 失败覆盖更早的安装 Failed。
- Good: `pnpm provision:core -NetworkMode China` 只转发根编排器，当前平台仍由 `Resolve-InstallPlatform` 决定。
- Bad: 新增 `install:core` 等脚本名，或在 pnpm 参数前添加 `--`。
- Bad: `[Console]::Out.WriteLine("{0} {1}" -f $first, $second)`；方法调用必须接收已完成格式化的单个字符串。

### 6. Tests Required

- 注册表：三平台目录、Core/Full、Step/FromStep/SkipStep、重复值、未知依赖、循环和 runner/path 校验。
- 执行：成功、Preview、退出 1/10、入口缺失、依赖传播、独立 verify、重跑命令和 JSON 日志隔离。
- source：Direct 零事务、China rollback、Auto 成功/失败/异常 cleanup、Restore 失败优先级。
- CLI：无参数和 `-installApp` 兼容、非法参数退出 2、ListSteps 与单文档 JSON。
- 默认测试不得执行真实安装或 China/Auto Apply；使用临时仓库、fixture 叶子和隔离状态。
- package scripts：`provision:list`、Core/Full preview smoke、参数透传，且不得触发 pnpm 依赖安装流程。
- Text 输出：标题、步骤、source restore 与最终状态的多占位符格式必须完整输出，不抛 `FormatException`。
- 进度：Text 启动行、长任务 elapsed heartbeat、JSON 静默，以及中断等待后无遗留直接子进程树。
- 代码完成后运行 `pnpm qa` 与 `pnpm test:pwsh:all`。

### 7. Wrong vs Correct

#### Wrong：命令拼接与条件清理

```powershell
# 拼接命令会破坏参数边界，且 source cleanup 不覆盖异常路径。
Invoke-Expression "pwsh $leafPath $arguments"
if ($runSucceeded) {
    ./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $transactionId
}
```

#### Correct：参数数组与 finally 清理

```powershell
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
foreach ($argument in @('-NoProfile', '-File', $leafPath) + $arguments) {
    $startInfo.ArgumentList.Add([string]$argument)
}

try {
    # 串行执行步骤并捕获 stdout/stderr。
}
finally {
    if ($networkMode -eq 'Auto' -and $transactionId) {
        ./scripts/pwsh/misc/Switch-Mirrors.ps1 `
            -Action Restore -TransactionId $transactionId -OutputFormat Json
    }
}
```

理由：参数数组保持命令边界，`finally` 保证 Auto 事务不依赖成功路径才恢复。

#### Wrong：方法调用内直接展开多参数格式表达式

```powershell
[Console]::Out.WriteLine("[{0}] {1}" -f $status, $name)
```

#### Correct：先规约为单个字符串参数

```powershell
[Console]::Out.WriteLine(("[{0}] {1}" -f $status, $name))
```

理由：外层括号先完成 `-f` 运算，再向 `WriteLine` 传递单个字符串；否则逗号可能被解析为方法参数分隔符。

#### Wrong：无限静默等待且只释放进程对象

```powershell
$process.WaitForExit()
$process.Dispose()
```

#### Correct：有限轮询只负责 heartbeat，中断路径清理进程树

```powershell
while (-not $process.WaitForExit(250)) {
    if ($showProgress -and $stopwatch.ElapsedMilliseconds -ge $nextHeartbeat) {
        [Console]::Error.WriteLine(("[Running] {0} {1} elapsed={2}s" -f $number, $id, $elapsedSeconds))
        $nextHeartbeat += 15000
    }
}

finally {
    if ($processStarted -and -not $process.HasExited) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $process.Dispose()
}
```

理由：250ms 轮询让 PowerShell 能处理 Ctrl+C，15 秒阈值只控制可观测 heartbeat，不是安装超时；`Kill(true)` 防止叶子退出后留下 fnm 等下载进程。
