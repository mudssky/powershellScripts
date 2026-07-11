<#
.SYNOPSIS
    组合 Windows winget 只读状态与共享语言生态 source 事务。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER TransactionId
    根编排器分配的 source transaction ID。

.PARAMETER OutputFormat
    Text 或 Json。

.OUTPUTS
    单个 source document；退出码来自共享语言 source 事务。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$TransactionId = '',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$switchMirrors = Join-Path $repoRoot 'scripts/pwsh/misc/Switch-Mirrors.ps1'
$bootstrapHelper = Join-Path $repoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'
if (-not (Test-Path -LiteralPath $switchMirrors -PathType Leaf)) {
    [Console]::Error.WriteLine("共享 source 引擎不存在: $switchMirrors")
    exit 1
}

$arguments = @{
    Action       = 'Apply'
    Mode         = $NetworkMode
    Phase        = 'Runtime'
    Target       = @('npm', 'pnpm', 'pip', 'go')
    OutputFormat = 'Json'
    WhatIf       = [bool]$WhatIfPreference
}
if (-not [string]::IsNullOrWhiteSpace($TransactionId)) {
    $arguments.TransactionId = $TransactionId
}

try {
    $sharedJson = (& $switchMirrors @arguments) -join "`n"
    $shared = $sharedJson | ConvertFrom-Json -ErrorAction Stop
    $wingetSnapshotStatus = 'Unavailable'
    if (Test-Path -LiteralPath $bootstrapHelper -PathType Leaf) {
        $stateRoot = if ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA 'powershellScripts/package-sources/bootstrap'
        }
        else {
            ''
        }
        $snapshotPath = if ($stateRoot) { Join-Path $stateRoot 'winget-source.json' } else { '' }
        $wingetSnapshotStatus = if ($snapshotPath -and (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { 'Prepared' } else { 'Direct' }
    }
    $wingetResult = [pscustomobject]@{
        Target        = 'winget'
        Mode          = $NetworkMode
        Phase         = 'Bootstrap'
        Adapter       = 'stage0-winget'
        Status        = 'Unsupported'
        Source        = ''
        Persistent    = $wingetSnapshotStatus -eq 'Prepared'
        TransactionId = ''
        Message       = "Stage 1 不修改 winget source；Stage 0 snapshot=$wingetSnapshotStatus"
        Rollback      = if ($wingetSnapshotStatus -eq 'Prepared') { './scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1 -Action Restore -Mode China' } else { '' }
    }
    $document = [pscustomobject]@{
        SchemaVersion = 1
        Action        = [string]$shared.Action
        Mode          = $NetworkMode
        TransactionId = [string]$shared.TransactionId
        ExitCode      = [int]$shared.ExitCode
        Results       = @($wingetResult) + @($shared.Results)
    }
    if ($shared.PSObject.Properties['Error']) {
        $document | Add-Member -NotePropertyName Error -NotePropertyValue $shared.Error
    }

    if ($OutputFormat -eq 'Json') {
        [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 12 -Compress))
    }
    else {
        foreach ($result in @($document.Results)) {
            Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Target, $result.Message)
        }
    }
    exit ([int]$document.ExitCode)
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
