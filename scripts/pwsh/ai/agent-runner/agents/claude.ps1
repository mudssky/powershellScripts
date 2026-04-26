Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    构造 `claude -p` 命令描述。

.DESCRIPTION
    将统一配置字段映射到 Claude Code 非交互模式。`reasoning_effort` 当前不映射，
    会记录在 UnsupportedOptions 中供 verbose 输出。

.PARAMETER Prompt
    要交给 agent 执行的 prompt。

.PARAMETER Config
    合并后的执行配置。

.OUTPUTS
    PSCustomObject
    返回可执行命令描述对象。
#>
function New-ClaudeAgentCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $workDir = if ($Config.ContainsKey('work_dir')) { [string]$Config.work_dir } else { (Get-Location).Path }
    $args = New-Object 'System.Collections.Generic.List[string]'
    foreach ($arg in @('-p', $Prompt, '--setting-sources', 'user,project,local')) {
        $args.Add($arg) | Out-Null
    }
    if ($Config.ContainsKey('model')) {
        $args.Add('--model') | Out-Null
        $args.Add([string]$Config.model) | Out-Null
    }
    if ($Config.ContainsKey('json') -and [bool]$Config.json) {
        $args.Add('--output-format') | Out-Null
        $args.Add('json') | Out-Null
    }
    if ($Config.ContainsKey('extra_args')) {
        foreach ($arg in @($Config.extra_args)) {
            $args.Add([string]$arg) | Out-Null
        }
    }

    $unsupported = @()
    if ($Config.ContainsKey('reasoning_effort')) {
        $unsupported += 'reasoning_effort'
    }

    return New-AiAgentCommandSpec -FilePath 'claude' -ArgumentList $args.ToArray() -WorkingDirectory $workDir -Prompt $Prompt -UnsupportedOptions $unsupported
}
