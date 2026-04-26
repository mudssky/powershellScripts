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

.PARAMETER InputText
    需要写入外部命令 stdin 的文本。

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

        [string]$InputText = '',

        [string[]]$UnsupportedOptions = @()
    )

    return [pscustomobject]@{
        FilePath           = $FilePath
        ArgumentList       = @($ArgumentList)
        WorkingDirectory   = $WorkingDirectory
        Prompt             = $Prompt
        InputText          = $InputText
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
        elseif ($arg -eq '-' -and -not [string]::IsNullOrEmpty([string]$Spec.InputText)) {
            $parts.Add('<PROMPT_STDIN>') | Out-Null
        }
        else {
            $parts.Add([string]$arg) | Out-Null
        }
    }

    return ("{0} {1}`nWorkDir={2}`nPromptChars={3}" -f $Spec.FilePath, ($parts -join ' '), $Spec.WorkingDirectory, $prompt.Length)
}

<#
.SYNOPSIS
    解析真实调用的 agent CLI 路径。

.DESCRIPTION
    Windows 上 npm 等工具常同时生成 `.ps1` 与 `.cmd` 包装器。PowerShell 脚本再次调用 `.ps1`
    包装器时，可能把标准流识别成非终端并触发 agent 的 TTY 检查错误；因此执行前优先选择
    `.cmd`、`.exe`、`.bat` 形式的应用包装器。预览仍保留原始命令名，避免泄露本机安装路径。

.PARAMETER FilePath
    命令规格中的外部 CLI 名称或路径。

.OUTPUTS
    string
    返回实际用于 `&` 调用的命令路径或名称。
#>
function Resolve-AiAgentInvocationFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $runsOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
    if (-not $runsOnWindows) {
        return $FilePath
    }

    if ([System.IO.Path]::IsPathRooted($FilePath) -or -not [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($FilePath))) {
        return $FilePath
    }

    foreach ($extension in @('.cmd', '.exe', '.bat')) {
        $candidate = Get-Command -Name "$FilePath$extension" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate.Source
        }
    }

    return $FilePath
}

<#
.SYNOPSIS
    执行外部 agent 命令并转发输出。

.DESCRIPTION
    PowerShell 函数会把外部命令 stdout 合并到自身成功输出流。runner 顶层需要用函数返回对象读取
    ExitCode，因此这里把 stdout 写到 host，避免 agent 日志污染结构化返回值。

.PARAMETER FilePath
    实际调用的外部 CLI 路径或名称。

.PARAMETER ArgumentList
    传递给外部 CLI 的参数数组。

.PARAMETER InputText
    需要写入外部命令 stdin 的文本。为空时不主动写入 stdin。

.OUTPUTS
    int
    返回外部命令的退出码。
#>
function Invoke-AiAgentNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$InputText = ''
    )

    if ([string]::IsNullOrEmpty($InputText)) {
        & $FilePath @ArgumentList | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        $InputText | & $FilePath @ArgumentList | ForEach-Object {
            Write-Host $_
        }
    }

    return $LASTEXITCODE
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

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf) -and -not (Get-Command -Name $FilePath -ErrorAction SilentlyContinue)) {
        throw "未找到 $FilePath，请先安装并完成登录。"
    }
}
