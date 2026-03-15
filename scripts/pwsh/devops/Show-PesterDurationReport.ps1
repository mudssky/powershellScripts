<#
.SYNOPSIS
    按耗时倒序汇总 Pester 文件级执行时间。

.DESCRIPTION
    支持两种输入方式：

    - `-Command`：执行命令，实时透传原始输出，再从完整日志中提取 Pester 文件级耗时
    - `-FilePath`：读取已有日志文件并生成排序报告

    该脚本主要服务于：

    - `pnpm test:pwsh:all`
    - `pnpm test:pwsh:coverage`
    - `pnpm test:pwsh:full`
    - `pnpm test:pwsh:full:assertions`
    - `pnpm test:pwsh:linux:full`

    当前实现仍基于控制台摘要行提取耗时，而不是直接消费 `Invoke-Pester -PassThru`。
    原因是 `test:pwsh:all` 的 Linux 路径仍通过 `docker compose` 外部进程执行，无法与 host 路径
    一样直接拿到同一进程里的 Pester 结果对象。脚本仍然使用 PowerShell 实现，方便后续若引入
    专用 harness 时平滑切到结构化结果。

.PARAMETER Command
    要执行的命令字符串，例如 `pnpm test:pwsh:all`。

.PARAMETER FilePath
    已存在的日志文件路径。

.PARAMETER Top
    仅显示最慢的前 N 个文件；默认显示全部。

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Show-PesterDurationReport.ps1 -Command 'pnpm test:pwsh:all' -Top 10

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Show-PesterDurationReport.ps1 -FilePath ./test.log -Top 5
#>

[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
    [Parameter(ParameterSetName = 'Command', Mandatory = $true)]
    [string]$Command,

    [Parameter(ParameterSetName = 'File', Mandatory = $true)]
    [string]$FilePath,

    [ValidateRange(1, 999)]
    [int]$Top = 999
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-AnsiEscapeSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    return [regex]::Replace($Text, '\x1B\[[0-9;]*m', '')
}

function Convert-PesterDurationToMilliseconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DurationText
    )

    if ($DurationText.EndsWith('ms')) {
        return [double]::Parse($DurationText.TrimEnd('m', 's'), [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return [double]::Parse($DurationText.TrimEnd('s'), [System.Globalization.CultureInfo]::InvariantCulture) * 1000
}

function Get-PesterDurationRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogText
    )

    $pattern = '^(?:\[(?<lane>[^\]]+)\]\s+)?\[\+\]\s+(?<path>.+?)\s+(?<duration>\d+(?:\.\d+)?(?:ms|s))\s+\('
    $rows = New-Object 'System.Collections.Generic.List[object]'

    foreach ($rawLine in ($LogText -split "\r?\n")) {
        $line = Remove-AnsiEscapeSequence -Text $rawLine
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) {
            continue
        }

        $lane = if ($match.Groups['lane'].Success) { $match.Groups['lane'].Value } else { 'single' }
        $pathText = $match.Groups['path'].Value.Trim()
        $durationText = $match.Groups['duration'].Value

        $rows.Add([PSCustomObject]@{
                Lane         = $lane
                Path         = $pathText
                DurationText = $durationText
                DurationMs   = Convert-PesterDurationToMilliseconds -DurationText $durationText
            }) | Out-Null
    }

    return @($rows | Sort-Object DurationMs -Descending)
}

function Show-PesterDurationRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [int]$Top
    )

    $limitedRows = if ($Rows.Count -gt $Top) { $Rows[0..($Top - 1)] } else { $Rows }
    if ($limitedRows.Count -eq 0) {
        Write-Warning '未在日志中找到 Pester 文件级耗时摘要。'
        return
    }

    $laneWidth = [Math]::Max(4, ($limitedRows | ForEach-Object { $_.Lane.Length } | Measure-Object -Maximum).Maximum)
    $durationWidth = [Math]::Max(8, ($limitedRows | ForEach-Object { $_.DurationText.Length } | Measure-Object -Maximum).Maximum)

    Write-Host ''
    Write-Host '=== Slowest Pester Files ===' -ForegroundColor Cyan
    Write-Host ("{0}  {1}  path" -f 'lane'.PadRight($laneWidth), 'duration'.PadRight($durationWidth))
    foreach ($row in $limitedRows) {
        Write-Host ("{0}  {1}  {2}" -f $row.Lane.PadRight($laneWidth), $row.DurationText.PadRight($durationWidth), $row.Path)
    }
}

function Invoke-CommandAndCaptureOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandText
    )

    $outputBuilder = [System.Text.StringBuilder]::new()
    $temporaryFile = [System.IO.Path]::GetTempFileName()

    try {
        # 通过临时文件承接 stdout/stderr，再回放到当前终端，避免丢失原始输出格式。
        cmd /d /c "$CommandText > `"$temporaryFile`" 2>&1"
        $exitCode = $LASTEXITCODE

        $rawOutput = if (Test-Path $temporaryFile) {
            Get-Content -Path $temporaryFile -Raw -Encoding utf8
        }
        else {
            ''
        }

        [void]$outputBuilder.Append($rawOutput)
        if (-not [string]::IsNullOrEmpty($rawOutput)) {
            Write-Host -NoNewline $rawOutput
        }

        return [PSCustomObject]@{
            ExitCode = $exitCode
            Output   = $outputBuilder.ToString()
        }
    }
    finally {
        Remove-Item -Path $temporaryFile -Force -ErrorAction SilentlyContinue
    }
}

$logText = ''
$exitCode = 0

if ($PSCmdlet.ParameterSetName -eq 'Command') {
    $result = Invoke-CommandAndCaptureOutput -CommandText $Command
    $exitCode = $result.ExitCode
    $logText = $result.Output
}
else {
    $resolvedFilePath = (Resolve-Path $FilePath).Path
    $logText = Get-Content -Path $resolvedFilePath -Raw -Encoding utf8
}

$rows = Get-PesterDurationRows -LogText $logText
Show-PesterDurationRows -Rows $rows -Top $Top

exit $exitCode
