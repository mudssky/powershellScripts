Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    构造 `codex exec` 命令描述。

.DESCRIPTION
    将统一配置字段映射到 Codex CLI 参数，包括模型、推理强度、JSON 输出和工作目录。

.PARAMETER Prompt
    要交给 agent 执行的 prompt。

.PARAMETER Config
    合并后的执行配置。

.OUTPUTS
    PSCustomObject
    返回可执行命令描述对象。
#>
function New-CodexAgentCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $workDir = if ($Config.ContainsKey('work_dir')) { [string]$Config.work_dir } else { (Get-Location).Path }
    $args = New-Object 'System.Collections.Generic.List[string]'
    $args.Add('exec') | Out-Null

    if ($Config.ContainsKey('model')) {
        $args.Add('--model') | Out-Null
        $args.Add([string]$Config.model) | Out-Null
    }
    if ($Config.ContainsKey('reasoning_effort')) {
        $args.Add('-c') | Out-Null
        $args.Add(('model_reasoning_effort="{0}"' -f [string]$Config.reasoning_effort)) | Out-Null
    }
    if ($Config.ContainsKey('json') -and [bool]$Config.json) {
        $args.Add('--json') | Out-Null
    }
    if ($Config.ContainsKey('extra_args')) {
        foreach ($arg in @($Config.extra_args)) {
            $args.Add([string]$arg) | Out-Null
        }
    }

    $args.Add('-C') | Out-Null
    $args.Add($workDir) | Out-Null
    $args.Add($Prompt) | Out-Null

    return New-AiAgentCommandSpec -FilePath 'codex' -ArgumentList $args.ToArray() -WorkingDirectory $workDir -Prompt $Prompt
}
