Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PackageSourceProcess {
    <#
    .SYNOPSIS
        在隔离子进程中执行 package source 外部命令。

    .DESCRIPTION
        统一捕获 stdout、stderr 和退出码，并支持为单次调用覆盖环境变量。
        当 FilePath 指向 ps1 文件时，使用当前 PowerShell 可执行文件启动。

    .PARAMETER FilePath
        要执行的可执行文件或 PowerShell 脚本路径。

    .PARAMETER ArgumentList
        传给外部命令的参数列表。

    .PARAMETER Environment
        仅对子进程生效的环境变量。

    .PARAMETER WorkingDirectory
        可选工作目录。

    .OUTPUTS
        PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [hashtable]$Environment = @{},

        [string]$WorkingDirectory = ''
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $isPowerShellScript = [System.IO.Path]::GetExtension($FilePath) -eq '.ps1'
    $startInfo.FileName = if ($isPowerShellScript) {
        (Get-Process -Id $PID).Path
    }
    else {
        $FilePath
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    if ($isPowerShellScript) {
        $startInfo.ArgumentList.Add('-NoLogo')
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-File')
        $startInfo.ArgumentList.Add($FilePath)
    }
    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add([string]$argument)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[[string]$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdoutTask.GetAwaiter().GetResult()
        StdErr   = $stderrTask.GetAwaiter().GetResult()
    }
}

function Resolve-ChsrcExecutablePath {
    <#
    .SYNOPSIS
        解析 chsrc 可执行文件路径。

    .DESCRIPTION
        测试与受控环境可通过环境变量覆盖路径；普通执行从 PATH 查找 chsrc。

    .OUTPUTS
        string。chsrc 可执行文件或测试脚本路径。
    #>
    [CmdletBinding()]
    param()

    $overridePath = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_CHSRC_PATH', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
        if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) {
            throw "指定的 chsrc 路径不存在: $overridePath"
        }
        return [System.IO.Path]::GetFullPath($overridePath)
    }

    $command = Get-Command chsrc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw '未找到 chsrc，请先通过平台包管理器安装稳定版'
    }

    return $command.Source
}

function Assert-ChsrcVersion {
    <#
    .SYNOPSIS
        验证 chsrc 版本满足 catalog 下限。

    .PARAMETER FilePath
        chsrc 可执行文件路径。

    .PARAMETER MinimumVersion
        允许的最低版本。

    .OUTPUTS
        System.Version。解析后的 chsrc 版本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [version]$MinimumVersion
    )

    $result = Invoke-PackageSourceProcess -FilePath $FilePath -ArgumentList @('--version')
    if ($result.ExitCode -ne 0) {
        throw "读取 chsrc 版本失败: $($result.StdErr.Trim())"
    }

    $match = [regex]::Match($result.StdOut, '(?i)\bv?(?<version>\d+\.\d+\.\d+)\b')
    if (-not $match.Success) {
        throw "无法解析 chsrc 版本: $($result.StdOut.Trim())"
    }

    $version = [version]$match.Groups['version'].Value
    if ($version -lt $MinimumVersion) {
        throw "chsrc 版本过低: $version，最低要求 $MinimumVersion"
    }

    return $version
}

function Get-PackageSourceFileHash {
    <#
    .SYNOPSIS
        返回文件 SHA-256；文件不存在时返回空字符串。

    .PARAMETER Path
        要计算 hash 的文件路径。

    .OUTPUTS
        string。小写 SHA-256 或空字符串。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Set-PackageSourceFileMode {
    <#
    .SYNOPSIS
        在 Unix 平台设置 package source 状态文件权限。

    .PARAMETER Path
        文件或目录路径。

    .PARAMETER Mode
        目标 Unix 权限。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.IO.UnixFileMode]$Mode
    )

    if ($IsWindows -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    [System.IO.File]::SetUnixFileMode($Path, $Mode)
}

function Write-PackageSourceTextAtomic {
    <#
    .SYNOPSIS
        以同目录临时文件原子写入文本。

    .PARAMETER Path
        目标文件路径。

    .PARAMETER Value
        要写入的完整文本。

    .OUTPUTS
        string。目标文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = Join-Path $directory ('.package-source.{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -LiteralPath $tempPath -Value $Value -Encoding utf8NoBOM -NoNewline
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    return $Path
}

function ConvertTo-SafePackageSourceUrl {
    <#
    .SYNOPSIS
        规范化 source URL 并移除可能包含凭据的部分。

    .DESCRIPTION
        只接受 HTTPS；输出移除 user-info、query 和 fragment，避免 registry token 进入结果或 manifest。

    .PARAMETER Value
        外部工具返回的 source URL。

    .OUTPUTS
        string。可安全展示的 HTTPS URL。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $candidate = $Value.Trim()
    $uri = $null
    if (-not [uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "package source 不是有效 HTTPS URL: $candidate"
    }

    $builder = [System.UriBuilder]::new($uri)
    $builder.UserName = ''
    $builder.Password = ''
    $builder.Query = ''
    $builder.Fragment = ''
    return $builder.Uri.AbsoluteUri
}

function New-PackageSourceAdapterException {
    <#
    .SYNOPSIS
        创建 adapter 可返回给公共入口的结构化异常。

    .PARAMETER Message
        面向用户的错误消息。

    .PARAMETER ExitCode
        CLI 退出码。

    .PARAMETER Code
        结构化错误代码。

    .OUTPUTS
        System.InvalidOperationException。Data 中包含 ExitCode 与 Code。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [int]$ExitCode = 1,

        [string]$Code = 'Failed'
    )

    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $ExitCode
    $exception.Data['Code'] = $Code
    return $exception
}

Export-ModuleMember -Function @(
    'Invoke-PackageSourceProcess'
    'Resolve-ChsrcExecutablePath'
    'Assert-ChsrcVersion'
    'Get-PackageSourceFileHash'
    'Set-PackageSourceFileMode'
    'Write-PackageSourceTextAtomic'
    'ConvertTo-SafePackageSourceUrl'
    'New-PackageSourceAdapterException'
)
