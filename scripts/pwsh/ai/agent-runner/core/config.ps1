Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    合并 AI agent 执行配置。

.DESCRIPTION
    以工具默认值、preset metadata、CLI 参数的顺序合并配置，
    让 CLI 显式参数具有最高优先级。

.PARAMETER Preset
    `Read-AiAgentPromptPreset` 返回的 preset 对象，可为空。

.PARAMETER CliParameters
    调用入口收到的显式 CLI 参数。

.OUTPUTS
    hashtable
    返回合并后的执行配置。
#>
function Resolve-AiAgentExecutionConfig {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [pscustomobject]$Preset,

        [hashtable]$CliParameters = @{}
    )

    $sources = New-Object 'System.Collections.Generic.List[hashtable]'
    $sources.Add(@{
            Type = 'Hashtable'
            Name = 'Defaults'
            Data = @{
                agent    = 'codex'
                work_dir = (Get-Location).Path
            }
        }) | Out-Null

    if ($null -ne $Preset) {
        $presetData = ConvertTo-ConfigHashtable -InputObject $Preset.Metadata
        $presetData['__content'] = $Preset.Content
        $sources.Add(@{
                Type = 'Hashtable'
                Name = 'PromptPreset'
                Data = $presetData
            }) | Out-Null
    }

    $sources.Add(@{
            Type        = 'CliParameters'
            Name        = 'Cli'
            Data        = $CliParameters
            ExcludeKeys = @('CommandName', 'Prompt', 'PromptFile', 'Preset', 'AppendPrompt', 'RawArguments')
        }) | Out-Null

    return (Resolve-ConfigSources -Sources $sources.ToArray()).Values
}
