<#
.SYNOPSIS
    Windows PowerShell 5.1 兼容的 Stage 0 source helper。

.DESCRIPTION
    Direct 不修改 source。China/Auto 仅在 Windows、管理员权限和 Microsoft.WinGet.Client
    结构化 source cmdlets 同时可用时管理 winget source，避免解析不可逆的表格文本。

.PARAMETER Action
    Run、Status 或 Restore。

.PARAMETER Mode
    Direct、China 或 Auto。

.PARAMETER Target
    Stage 0 target，当前仅支持 winget。

.PARAMETER ConfigPath
    严格 KEY=VALUE bootstrap 配置路径。

.PARAMETER FilePath
    source 准备完成后执行的命令。

.PARAMETER ArgumentList
    传给 FilePath 的参数。

.PARAMETER StateRoot
    可选 bootstrap 状态目录。

.PARAMETER DryRun
    只输出计划。

.PARAMETER OutputFormat
    Text 或 Json。
#>
[CmdletBinding()]
param(
    [ValidateSet('Run', 'Status', 'Restore')]
    [string]$Action = 'Run',

    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$Mode = 'Direct',

    [ValidateSet('winget')]
    [string]$Target = 'winget',

    [string]$ConfigPath = '',

    [string]$FilePath = '',

    [string[]]$ArgumentList = @(),

    [string]$StateRoot = '',

    [switch]$DryRun,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-BootstrapResult {
    <#
    .SYNOPSIS
        写入 Stage 0 结构化或文本结果。

    .PARAMETER Status
        结果状态。

    .PARAMETER Message
        面向用户的说明。

    .PARAMETER ExitCode
        约定退出码。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [int]$ExitCode = 0
    )

    if ($OutputFormat -eq 'Json') {
        [PSCustomObject][ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = $Mode
            Target        = $Target
            Status        = $Status
            ExitCode      = $ExitCode
            Message       = $Message
        } | ConvertTo-Json -Depth 5
        return
    }

    Write-Output ('[{0}] {1}: {2}' -f $Status, $Target, $Message)
}

function Read-BootstrapEnvValue {
    <#
    .SYNOPSIS
        从严格 KEY=VALUE 文件读取单个非敏感配置。

    .PARAMETER Path
        bootstrap env 文件。

    .PARAMETER Name
        要读取的变量名。

    .OUTPUTS
        string。配置值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Stage 0 配置不存在: $Path"
    }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        $parts = $trimmed.Split(@('='), 2)
        if ($parts.Count -ne 2) {
            throw 'Stage 0 配置包含非法行'
        }
        if ($parts[0] -eq $Name) {
            return $parts[1]
        }
    }
    throw "Stage 0 配置缺少变量: $Name"
}

function Resolve-BootstrapStateRoot {
    <#
    .SYNOPSIS
        解析 Windows Stage 0 状态目录。

    .OUTPUTS
        string。bootstrap 状态根目录。
    #>
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($StateRoot)) {
        return [System.IO.Path]::GetFullPath($StateRoot)
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw '无法解析 LOCALAPPDATA'
    }
    return Join-Path $env:LOCALAPPDATA 'powershellScripts\package-sources\bootstrap'
}

function Test-WindowsAdministrator {
    <#
    .SYNOPSIS
        判断当前 Windows 进程是否具有管理员权限。

    .OUTPUTS
        bool。管理员进程为 true。
    #>
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return $false
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WingetSourceSnapshotPath {
    <#
    .SYNOPSIS
        返回 winget bootstrap snapshot 路径。

    .OUTPUTS
        string。snapshot JSON 路径。
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Resolve-BootstrapStateRoot) 'winget-source.json'
}

function Save-WingetSourceSnapshot {
    <#
    .SYNOPSIS
        保存当前 winget source 的结构化 snapshot。

    .OUTPUTS
        string。snapshot 路径。
    #>
    [CmdletBinding()]
    param()

    $source = Get-WinGetSource | Where-Object { $_.Name -eq 'winget' } | Select-Object -First 1
    if ($null -eq $source) {
        throw '未找到 winget source'
    }

    $path = Get-WingetSourceSnapshotPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return $path
    }

    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $snapshot = [PSCustomObject][ordered]@{
        Name       = [string]$source.Name
        Argument   = [string]$source.Argument
        Type       = [string]$source.Type
        TrustLevel = [string]$source.TrustLevel
        Explicit   = [bool]$source.Explicit
    }
    $tempPath = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        Move-Item -LiteralPath $tempPath -Destination $path -Force
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    return $path
}

function Restore-WingetSourceSnapshot {
    <#
    .SYNOPSIS
        从结构化 snapshot 恢复 winget source。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    $path = Get-WingetSourceSnapshotPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "winget bootstrap snapshot 不存在: $path"
    }
    $snapshot = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $current = Get-WinGetSource | Where-Object { $_.Name -eq $snapshot.Name } | Select-Object -First 1
    if ($null -ne $current) {
        Remove-WinGetSource -Name ([string]$snapshot.Name)
    }
    $parameters = @{
        Name       = [string]$snapshot.Name
        Argument   = [string]$snapshot.Argument
        Type       = [string]$snapshot.Type
        TrustLevel = [string]$snapshot.TrustLevel
    }
    if ([bool]$snapshot.Explicit) {
        $parameters['Explicit'] = $true
    }
    Add-WinGetSource @parameters
    Remove-Item -LiteralPath $path -Force
}

function Assert-WingetBootstrapCapability {
    <#
    .SYNOPSIS
        验证 winget Stage 0 source 修改前置。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'winget Stage 0 只能在 Windows 执行'
    }
    if (-not (Test-WindowsAdministrator)) {
        throw 'winget source 修改需要管理员权限'
    }
    foreach ($commandName in @('Get-WinGetSource', 'Add-WinGetSource', 'Remove-WinGetSource')) {
        if ($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw '缺少 Microsoft.WinGet.Client 结构化 source cmdlets'
        }
    }
}

function Invoke-BootstrapCommand {
    <#
    .SYNOPSIS
        执行 Stage 0 后续命令。

    .OUTPUTS
        int。子命令退出码。
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return 0
    }
    & $FilePath @ArgumentList
    if ($null -eq $LASTEXITCODE) {
        return 0
    }
    return [int]$LASTEXITCODE
}

try {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $ConfigPath = Join-Path $repoRoot 'config\network\package-sources.bootstrap.env'
    }

    if ($Action -eq 'Status') {
        $snapshotPath = Get-WingetSourceSnapshotPath
        $status = if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) { 'Prepared' } else { 'Direct' }
        Write-BootstrapResult -Status $status -Message 'winget bootstrap snapshot 状态'
        exit 0
    }
    if ($Action -eq 'Restore') {
        Assert-WingetBootstrapCapability
        Restore-WingetSourceSnapshot
        Write-BootstrapResult -Status 'Restored' -Message '已恢复原 winget source'
        exit 0
    }

    if ($Mode -eq 'Direct') {
        Write-BootstrapResult -Status 'Direct' -Message '保持官方或现有 winget source'
        if ($DryRun) {
            exit 0
        }
        exit (Invoke-BootstrapCommand)
    }

    Assert-WingetBootstrapCapability
    if ($Mode -eq 'Auto') {
        try {
            $null = Invoke-WebRequest -Uri 'https://cdn.winget.microsoft.com/cache' -Method Head -TimeoutSec 5 -UseBasicParsing
            Write-BootstrapResult -Status 'Official' -Message '官方 winget source 可用'
            if ($DryRun) {
                exit 0
            }
            exit (Invoke-BootstrapCommand)
        }
        catch {
        }
    }

    $mirrorUrl = Read-BootstrapEnvValue -Path $ConfigPath -Name 'WINGET_SOURCE_URL'
    if (-not $mirrorUrl.StartsWith('https://')) {
        throw 'WINGET_SOURCE_URL 必须使用 HTTPS'
    }
    if ($DryRun) {
        Write-BootstrapResult -Status 'Prepared' -Message '将临时切换 winget source'
        exit 0
    }

    $null = Save-WingetSourceSnapshot
    $current = Get-WinGetSource | Where-Object { $_.Name -eq 'winget' } | Select-Object -First 1
    if ($null -ne $current) {
        Remove-WinGetSource -Name 'winget'
    }
    Add-WinGetSource -Name 'winget' -Argument $mirrorUrl -Type 'Microsoft.PreIndexed.Package' -TrustLevel 'Trusted'
    Write-BootstrapResult -Status 'Prepared' -Message 'winget source 已切换'

    if ($Mode -eq 'Auto') {
        try {
            $commandExitCode = Invoke-BootstrapCommand
        }
        finally {
            Restore-WingetSourceSnapshot
        }
        exit $commandExitCode
    }

    exit (Invoke-BootstrapCommand)
}
catch {
    Write-BootstrapResult -Status 'Blocked' -Message $_.Exception.Message -ExitCode 10
    exit 10
}
