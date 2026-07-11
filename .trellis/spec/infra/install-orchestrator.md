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

- 无参数调用保持仓库工具准备行为；不得隐式转为装机。
- `-installApp` 仅为弃用兼容入口，不等价于 Full，也不能与编排参数组合；Linux 分支只转发到新的 Core CLI 叶子。
- Stage 0 获得 Git、平台包管理器和 PowerShell 7；根 Stage 1 从 `03 sources` 开始。
- `Core` 选择 `03`～`07` 与 `99`；`Full` 追加 `08`～`11`。
- `-Step` 精准执行且不展开依赖；`-FromStep` 假定前序已完成；`-SkipStep` 排除依赖时阻断下游。

### 3. Contracts

- `config/install/steps.psd1` 是编号、Preset、依赖和平台未来路径的唯一真源，只允许 data literal。
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

### 5. Good/Base/Bad Cases

- Good: 平台任务只新增注册表声明对应的薄叶子，根编排器无需复制 Homebrew、apt、winget 或 profile 业务。
- Good: Auto source 步骤失败但返回事务 ID 时，仍在 finally 恢复已修改资源。
- Base: Direct 模式仍执行 `03 sources` 的结构化 no-op，以便汇总保持相同步骤模型，但不创建事务。
- Bad: 叶子缺失时调用旧编号脚本并把运行标为成功。
- Bad: JSON 模式让叶子日志直通 stdout，或 cleanup 失败覆盖更早的安装 Failed。

### 6. Tests Required

- 注册表：三平台目录、Core/Full、Step/FromStep/SkipStep、重复值、未知依赖、循环和 runner/path 校验。
- 执行：成功、Preview、退出 1/10、入口缺失、依赖传播、独立 verify、重跑命令和 JSON 日志隔离。
- source：Direct 零事务、China rollback、Auto 成功/失败/异常 cleanup、Restore 失败优先级。
- CLI：无参数和 `-installApp` 兼容、非法参数退出 2、ListSteps 与单文档 JSON。
- 默认测试不得执行真实安装或 China/Auto Apply；使用临时仓库、fixture 叶子和隔离状态。
- 代码完成后运行 `pnpm qa` 与 `pnpm test:pwsh:all`。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 拼接命令会破坏参数边界，且 source cleanup 不覆盖异常路径。
Invoke-Expression "pwsh $leafPath $arguments"
if ($runSucceeded) {
    ./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $transactionId
}
```

#### Correct

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

理由：参数数组保持命令边界，finally 保证 Auto 事务不依赖成功路径才恢复。
