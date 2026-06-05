Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    格式化原生命令为可读命令行。

.DESCRIPTION
    将命令名和参数数组渲染成一行文本，供 dry-run、日志和 ShouldProcess action 使用。
    该函数只负责展示文本，不参与 shell 拼接或执行。

.PARAMETER Command
    命令名或可执行文件路径。

.PARAMETER ArgumentList
    传递给命令的参数数组。

.OUTPUTS
    string。可读命令行文本。
#>
function Format-NativeCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$ArgumentList = @()
    )

    $parts = @($Command) + @($ArgumentList)
    return ($parts | ForEach-Object {
            $value = [string]$_
            if ($value -match '\s' -or $value -match '["'']') {
                '"' + ($value -replace '"', '\"') + '"'
            }
            else {
                $value
            }
        }) -join ' '
}

<#
.SYNOPSIS
    解析可交给 ProcessStartInfo 的外部命令路径。

.DESCRIPTION
    `System.Diagnostics.ProcessStartInfo` 不会像 PowerShell 一样自动处理函数、
    alias 或脚本包装器。这里优先选择 Application 类型，避免 Windows 上误选
    npm 生成的 `.ps1` wrapper；找不到时返回原始命令名，由进程启动阶段报错。

.PARAMETER Command
    命令名或可执行文件路径。

.OUTPUTS
    string。可传给 ProcessStartInfo.FileName 的路径或命令名。
#>
function Resolve-NativeExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    if ([System.IO.Path]::IsPathRooted($Command)) {
        return $Command
    }

    $commands = @(Get-Command -Name $Command -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        return $Command
    }

    $application = $commands | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($application) {
        return $application.Source
    }

    $externalScript = $commands | Where-Object { $_.CommandType -eq 'ExternalScript' } | Select-Object -First 1
    if ($externalScript) {
        return $externalScript.Source
    }

    return $commands[0].Source
}

<#
.SYNOPSIS
    创建命令日志文件。

.PARAMETER LogDirectory
    日志目录路径。

.PARAMETER Prefix
    日志文件名前缀；默认使用 `command`。

.PARAMETER Header
    日志首行内容；为空时使用前缀和时间戳生成。

.OUTPUTS
    string。日志文件绝对路径。
#>
function New-CommandLogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'command',

        [AllowEmptyString()]
        [string]$Header = ''
    )

    $resolvedDirectory = [System.IO.Path]::GetFullPath($LogDirectory)
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $resolvedDirectory "$Prefix-$timestamp.log"
    $logHeader = if ([string]::IsNullOrWhiteSpace($Header)) { "$Prefix log $timestamp" } else { $Header }
    Set-Content -LiteralPath $logPath -Encoding utf8NoBOM -Value $logHeader
    return $logPath
}

<#
.SYNOPSIS
    写入单行命令日志。

.PARAMETER LogPath
    日志文件路径。为空时不写入。

.PARAMETER Message
    日志消息。

.OUTPUTS
    None。追加日志内容。
#>
function Write-CommandLogLine {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Encoding utf8NoBOM -Value $line
}

<#
.SYNOPSIS
    执行外部原生命令并记录输出。

.DESCRIPTION
    使用 `System.Diagnostics.Process` 执行命令，捕获 stdout、stderr 和退出码。
    默认会把 stdout/stderr 继续转发到控制台，同时写入日志；静默检查场景可用
    `-SuppressOutput` 仅保留日志和结构化返回值。

.PARAMETER Command
    命令名或可执行文件路径。

.PARAMETER ArgumentList
    传递给命令的参数数组。

.PARAMETER WorkingDirectory
    命令工作目录。

.PARAMETER LogPath
    可选日志文件路径。

.PARAMETER AllowFailure
    为真时命令非零退出也返回结果，不抛异常。

.PARAMETER SuppressOutput
    为真时不向控制台转发 stdout/stderr，但仍记录到日志。

.OUTPUTS
    PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
#>
function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory = (Get-Location).Path,

        [AllowEmptyString()]
        [string]$LogPath = '',

        [switch]$AllowFailure,

        [switch]$SuppressOutput
    )

    $commandLine = Format-NativeCommandLine -Command $Command -ArgumentList $ArgumentList
    Write-CommandLogLine -LogPath $LogPath -Message "COMMAND $commandLine"
    Write-CommandLogLine -LogPath $LogPath -Message "CWD $WorkingDirectory"
    Write-Verbose ("执行外部命令: {0}" -f $commandLine)
    Write-Verbose ("外部命令工作目录: {0}" -f $WorkingDirectory)
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Write-Verbose ("外部命令日志: {0}" -f $LogPath)
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Resolve-NativeExecutablePath -Command $Command
    Write-Verbose ("外部命令可执行文件: {0}" -f $startInfo.FileName)
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        Write-Verbose ("外部命令已启动，PID: {0}" -f $process.Id)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($stdout) -and -not $SuppressOutput) {
        [Console]::Out.Write($stdout)
    }
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-CommandLogLine -LogPath $LogPath -Message "STDOUT $($stdout.TrimEnd())"
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr) -and -not $SuppressOutput) {
        [Console]::Error.Write($stderr)
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-CommandLogLine -LogPath $LogPath -Message "STDERR $($stderr.TrimEnd())"
    }

    Write-CommandLogLine -LogPath $LogPath -Message "EXIT $exitCode"
    Write-Verbose ("外部命令退出码: {0}" -f $exitCode)
    $result = [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "外部命令执行失败($exitCode): $commandLine"
    }

    return $result
}

Export-ModuleMember -Function @(
    'Format-NativeCommandLine'
    'Resolve-NativeExecutablePath'
    'New-CommandLogFile'
    'Write-CommandLogLine'
    'Invoke-NativeCommand'
)
