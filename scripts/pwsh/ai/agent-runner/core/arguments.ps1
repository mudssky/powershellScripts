Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    将顶层命令转换为 run 请求。

.DESCRIPTION
    把 `commit` 快捷命令规约为 `run -Preset commit`，让后续执行路径统一。

.PARAMETER CommandName
    顶层命令名。

.PARAMETER Prompt
    直接 prompt 文本。

.PARAMETER PromptFile
    prompt 文件路径。

.PARAMETER Preset
    preset 名称。

.OUTPUTS
    PSCustomObject
    返回标准化请求。
#>
function ConvertTo-AiAgentRunRequest {
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string]$Prompt,
        [string]$PromptFile,
        [string]$Preset
    )

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        $CommandName = 'help'
    }

    switch ($CommandName) {
        'commit' {
            return [pscustomobject]@{
                CommandName = 'run'
                Prompt      = $null
                PromptFile  = $null
                Preset      = 'commit'
            }
        }
        'run' {
            return [pscustomobject]@{
                CommandName = 'run'
                Prompt      = $Prompt
                PromptFile  = $PromptFile
                Preset      = $Preset
            }
        }
        'help' {
            return [pscustomobject]@{
                CommandName = 'help'
                Prompt      = $null
                PromptFile  = $null
                Preset      = $null
            }
        }
        default {
            throw "未知命令: $CommandName"
        }
    }
}
