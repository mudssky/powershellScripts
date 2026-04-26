Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    创建 AI agent 外部命令描述。

.DESCRIPTION
    把可执行文件、参数、工作目录和原始 prompt 收口为一个稳定对象，
    便于 dry-run、测试和真实执行复用。

.PARAMETER FilePath
    外部 CLI 名称或路径。

.PARAMETER ArgumentList
    外部 CLI 参数数组。

.PARAMETER WorkingDirectory
    命令工作目录。

.PARAMETER Prompt
    原始 prompt 文本，仅用于统计长度，不在预览中明文打印。

.PARAMETER UnsupportedOptions
    当前 agent 不支持的统一配置字段。

.OUTPUTS
    PSCustomObject
    返回命令描述对象。
#>
function New-AiAgentCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [string]$WorkingDirectory = (Get-Location).Path,

        [string]$Prompt = '',

        [string[]]$UnsupportedOptions = @()
    )

    return [pscustomobject]@{
        FilePath           = $FilePath
        ArgumentList       = @($ArgumentList)
        WorkingDirectory   = $WorkingDirectory
        Prompt             = $Prompt
        UnsupportedOptions = @($UnsupportedOptions)
    }
}

<#
.SYNOPSIS
    生成安全的 agent 命令预览。

.DESCRIPTION
    命令预览会隐藏完整 prompt，只显示 `<PROMPT>` 与字符数，避免日志过长或泄露任务细节。

.PARAMETER Spec
    `New-AiAgentCommandSpec` 返回的命令描述对象。

.OUTPUTS
    string
    返回可打印的命令预览。
#>
function Format-AiAgentCommandPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec
    )

    $prompt = [string]$Spec.Prompt
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($arg in @($Spec.ArgumentList)) {
        if ($arg -eq $prompt -and -not [string]::IsNullOrEmpty($prompt)) {
            $parts.Add('<PROMPT>') | Out-Null
        }
        else {
            $parts.Add([string]$arg) | Out-Null
        }
    }

    return ("{0} {1}`nWorkDir={2}`nPromptChars={3}" -f $Spec.FilePath, ($parts -join ' '), $Spec.WorkingDirectory, $prompt.Length)
}

<#
.SYNOPSIS
    检查外部 agent CLI 是否可用。

.DESCRIPTION
    使用 `Get-Command` 检查命令存在性，并返回中文错误供 runner 顶层展示。

.PARAMETER FilePath
    外部 CLI 名称或路径。

.OUTPUTS
    void
    命令不存在时抛出异常。
#>
function Assert-AiAgentCommandAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Get-Command -Name $FilePath -ErrorAction SilentlyContinue)) {
        throw "未找到 $FilePath，请先安装并完成登录。"
    }
}
