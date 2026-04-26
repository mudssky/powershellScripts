#!/usr/bin/env pwsh
<#
.SYNOPSIS
    通过本机 coding agent 执行 prompt 或内置 preset。

.DESCRIPTION
    支持 `codex`、`claude`、`opencode` 三个 agent，并通过 Markdown preset 管理常用任务。

.PARAMETER CommandName
    顶层命令，支持 `run`、`commit`、`help`。

.PARAMETER Prompt
    直接执行的 prompt 文本。

.PARAMETER PromptFile
    prompt 文件路径。

.PARAMETER Preset
    prompt preset 名称。

.PARAMETER AppendPrompt
    追加到最终 prompt 尾部的附加要求。
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$CommandName,

    [Parameter(Position = 1)]
    [string]$Prompt,

    [string]$PromptFile,
    [string]$Preset,

    [ValidateSet('codex', 'claude', 'opencode')]
    [string]$Agent,

    [string]$Model,

    [ValidateSet('minimal', 'low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort,

    [string]$WorkDir,
    [switch]$Json,
    [switch]$DryRun,
    [string[]]$AppendPrompt,
    [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ConfigSourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..' 'psutils/src/config'))
foreach ($relativePath in @('convert.ps1', 'discovery.ps1', 'reader.ps1', 'resolver.ps1', 'scoped-environment.ps1')) {
    . (Join-Path $ConfigSourceRoot $relativePath)
}
foreach ($relativePath in @(
        'core/process.ps1'
        'core/prompt.ps1'
        'core/config.ps1'
        'core/arguments.ps1'
        'agents/codex.ps1'
        'agents/claude.ps1'
        'agents/opencode.ps1'
    )) {
    . (Join-Path $PSScriptRoot $relativePath)
}

<#
.SYNOPSIS
    返回 AI agent runner 帮助文本。

.DESCRIPTION
    生成静态帮助文本，供 `help` 命令和空命令输出。

.OUTPUTS
    string
    返回帮助文本。
#>
function Get-AiAgentHelpText {
    [CmdletBinding()]
    param()

    return @'
Usage:
  Invoke-AiAgent.ps1 commit [-AppendPrompt "只提交暂存区"]
  Invoke-AiAgent.ps1 fix-tests [-AppendPrompt "只修复 Pester 失败"]
  Invoke-AiAgent.ps1 run "prompt text" [-Agent codex]
  Invoke-AiAgent.ps1 run -PromptFile ./task.md [-AppendPrompt "不要修改文档"]
  Invoke-AiAgent.ps1 run -Preset commit [-ReasoningEffort high]

Commands:
  commit      使用内置 commit preset 执行 git commit，不 push
  fix-tests   使用内置 fix-tests preset 定位并修复测试失败，不提交
  run         执行自定义 prompt、prompt 文件或 preset
  help        显示帮助
'@
}

<#
.SYNOPSIS
    执行 AI agent runner 顶层命令。

.DESCRIPTION
    标准化命令请求，解析 prompt 与配置，构造对应 agent 命令并执行或 dry-run。

.PARAMETER BoundParameters
    入口收到的 `$PSBoundParameters`。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的结果对象。
#>
function Invoke-AiAgentRunnerCommand {
    [CmdletBinding()]
    param(
        [hashtable]$BoundParameters
    )

    $request = ConvertTo-AiAgentRunRequest `
        -CommandName $CommandName `
        -Prompt $Prompt `
        -PromptFile $PromptFile `
        -Preset $Preset

    if ($request.CommandName -eq 'help') {
        return [pscustomobject]@{ ExitCode = 0; Output = Get-AiAgentHelpText }
    }

    $promptsRoot = Join-Path $PSScriptRoot 'prompts'
    $presetObject = if (-not [string]::IsNullOrWhiteSpace($request.Preset)) {
        Read-AiAgentPromptPreset -Name $request.Preset -PromptsRoot $promptsRoot
    }
    else {
        $null
    }

    $config = Resolve-AiAgentExecutionConfig -Preset $presetObject -CliParameters $BoundParameters
    $appendPromptItems = if ($BoundParameters.ContainsKey('AppendPrompt')) {
        @($BoundParameters['AppendPrompt'])
    }
    else {
        @()
    }

    $promptText = Resolve-AiAgentPromptText `
        -Prompt $request.Prompt `
        -PromptFile $request.PromptFile `
        -PresetName $request.Preset `
        -PromptsRoot $promptsRoot `
        -AppendPrompt $appendPromptItems

    switch ([string]$config.agent) {
        'codex' { $spec = New-CodexAgentCommandSpec -Prompt $promptText -Config $config }
        'claude' { $spec = New-ClaudeAgentCommandSpec -Prompt $promptText -Config $config }
        'opencode' { $spec = New-OpenCodeAgentCommandSpec -Prompt $promptText -Config $config }
        default { throw "不支持的 agent: $($config.agent)" }
    }

    if ($DryRun) {
        return [pscustomobject]@{ ExitCode = 0; Output = Format-AiAgentCommandPreview -Spec $spec }
    }

    $invocationFilePath = Resolve-AiAgentInvocationFilePath -FilePath $spec.FilePath
    Assert-AiAgentCommandAvailable -FilePath $invocationFilePath
    Push-Location $spec.WorkingDirectory
    try {
        $exitCode = Invoke-AiAgentNativeCommand -FilePath $invocationFilePath -ArgumentList @($spec.ArgumentList) -InputText ([string]$spec.InputText)
        return [pscustomobject]@{ ExitCode = $exitCode; Output = '' }
    }
    finally {
        Pop-Location
    }
}

if ($env:PWSH_TEST_SKIP_AI_AGENT_RUNNER_MAIN -ne '1') {
    try {
        $result = Invoke-AiAgentRunnerCommand -BoundParameters $PSBoundParameters
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            Write-Output $result.Output
        }
        exit $result.ExitCode
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
