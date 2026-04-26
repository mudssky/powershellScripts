Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    构造 `opencode run` 命令描述。

.DESCRIPTION
    将统一配置字段映射到 OpenCode CLI。`reasoning_effort` 与统一 `json` 开关当前不映射，
    可通过 `extra_args` 透传 OpenCode 自有参数。

.PARAMETER Prompt
    要交给 agent 执行的 prompt。

.PARAMETER Config
    合并后的执行配置。

.OUTPUTS
    PSCustomObject
    返回可执行命令描述对象。
#>
function New-OpenCodeAgentCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $workDir = if ($Config.ContainsKey('work_dir')) { [string]$Config.work_dir } else { (Get-Location).Path }
    $args = New-Object 'System.Collections.Generic.List[string]'
    $args.Add('run') | Out-Null
    $args.Add($Prompt) | Out-Null
    if ($Config.ContainsKey('model')) {
        $args.Add('--model') | Out-Null
        $args.Add([string]$Config.model) | Out-Null
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
    if ($Config.ContainsKey('json') -and [bool]$Config.json) {
        $unsupported += 'json'
    }

    return New-AiAgentCommandSpec -FilePath 'opencode' -ArgumentList $args.ToArray() -WorkingDirectory $workDir -Prompt $Prompt -UnsupportedOptions $unsupported
}
