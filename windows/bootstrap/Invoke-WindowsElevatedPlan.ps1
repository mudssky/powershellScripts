<#
.SYNOPSIS
    在单个管理员子进程中执行受限 Windows 机器安装计划。

.PARAMETER PlanPath
    普通用户进程写入的 JSON plan 路径。

.PARAMETER ResultPath
    结构化 JSON 结果写回路径。

.PARAMETER SourceHelperPath
    固定的 winget Stage 0 source helper 路径。

.PARAMETER SourceConfigPath
    固定的 Stage 0 source 配置路径。

.OUTPUTS
    不向 stdout 输出业务结果；结果写入 ResultPath。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PlanPath,

    [Parameter(Mandatory)]
    [string]$ResultPath,

    [Parameter(Mandatory)]
    [string]$SourceHelperPath,

    [Parameter(Mandatory)]
    [string]$SourceConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ElevatedAdministrator {
    <#
    .SYNOPSIS
        验证当前执行器确实运行在管理员上下文。

    .OUTPUTS
        System.Boolean。管理员进程返回 true。
    #>
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-ElevatedResult {
    <#
    .SYNOPSIS
        创建单个提升 operation 结果。

    .PARAMETER Name
        operation 组件名。

    .PARAMETER Status
        Succeeded、Failed 或 RestartRequired。

    .PARAMETER Message
        诊断摘要。

    .PARAMETER ExitCode
        原生命令退出码。

    .OUTPUTS
        PSCustomObject。单个 operation 结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'Failed', 'RestartRequired')]
        [string]$Status,

        [string]$Message = '',

        [int]$ExitCode = 0
    )

    return [pscustomobject]@{ Name = $Name; Status = $Status; Message = $Message; ExitCode = $ExitCode }
}

function Test-ElevatedInstallerSignature {
    <#
    .SYNOPSIS
        在提升进程内再次验证本地安装包 Authenticode 签名。

    .PARAMETER Path
        MSI 或 EXE 安装包路径。

    .OUTPUTS
        System.Boolean。签名有效时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return (Get-AuthenticodeSignature -LiteralPath $Path).Status -eq 'Valid'
}

function Invoke-ElevatedProcess {
    <#
    .SYNOPSIS
        执行固定可执行文件和参数数组并规约退出状态。

    .PARAMETER Name
        operation 组件名。

    .PARAMETER FilePath
        固定可执行文件路径。

    .PARAMETER ArgumentList
        由执行器代码生成的参数数组。

    .OUTPUTS
        PSCustomObject。单个 operation 结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList
    )

    $output = @(& $FilePath @ArgumentList 2>&1)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $message = ($output | Select-Object -Last 20 | Out-String).Trim()
    if ($exitCode -in @(1641, 3010)) {
        return New-ElevatedResult -Name $Name -Status RestartRequired -Message $message -ExitCode $exitCode
    }
    if ($exitCode -ne 0) {
        return New-ElevatedResult -Name $Name -Status Failed -Message $(if ($message) { $message } else { "命令退出码为 $exitCode" }) -ExitCode $exitCode
    }
    return New-ElevatedResult -Name $Name -Status Succeeded -Message $message
}

function Assert-ElevatedOperation {
    <#
    .SYNOPSIS
        校验 operation 类型、组件和字段白名单。

    .PARAMETER Operation
        从 plan 反序列化的 operation。

    .OUTPUTS
        None。非法 operation 抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Operation
    )

    if ([string]$Operation.Type -notin @('WingetInstall', 'MsiInstall', 'ExeInstaller', 'WslInstall')) {
        throw "不允许的 operation 类型: $($Operation.Type)"
    }
    if ([string]$Operation.Name -notin @('Git', 'PowerShell', 'AutoHotkey', 'Wsl')) {
        throw "不允许的 operation 组件: $($Operation.Name)"
    }
    switch ([string]$Operation.Type) {
        'WingetInstall' {
            $allowedIds = @{
                Git        = 'Git.Git'
                PowerShell = 'Microsoft.PowerShell'
                AutoHotkey = 'AutoHotkey.AutoHotkey'
            }
            if (-not $allowedIds.ContainsKey([string]$Operation.Name) -or
                [string]$Operation.Id -ne [string]$allowedIds[[string]$Operation.Name]) {
                throw "WingetInstall package ID 不在 allowlist: $($Operation.Name)/$($Operation.Id)"
            }
        }
        'MsiInstall' {
            if ([string]$Operation.Name -ne 'PowerShell' -or
                [System.IO.Path]::GetExtension([string]$Operation.Path) -ine '.msi' -or
                -not (Test-ElevatedInstallerSignature -Path ([string]$Operation.Path))) {
                throw 'MsiInstall 仅允许签名有效的 PowerShell MSI'
            }
        }
        'ExeInstaller' {
            if ([string]$Operation.Name -notin @('Git', 'AutoHotkey') -or
                [System.IO.Path]::GetExtension([string]$Operation.Path) -ine '.exe' -or
                -not (Test-ElevatedInstallerSignature -Path ([string]$Operation.Path))) {
                throw 'ExeInstaller 仅允许签名有效的 Git 或 AutoHotkey 安装包'
            }
        }
        'WslInstall' {
            if ([string]$Operation.Name -ne 'Wsl' -or [string]$Operation.Distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') {
                throw 'WslInstall 缺少合法发行版名称'
            }
        }
    }
}

$results = New-Object System.Collections.Generic.List[object]
$document = $null
try {
    if (-not (Test-ElevatedAdministrator)) {
        throw '提升执行器未获得管理员权限'
    }
    $assetRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $expectedSourceHelper = [System.IO.Path]::GetFullPath((Join-Path $assetRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'))
    $expectedSourceConfig = [System.IO.Path]::GetFullPath((Join-Path $assetRoot 'config/network/package-sources.bootstrap.env'))
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($SourceHelperPath), $expectedSourceHelper, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([System.IO.Path]::GetFullPath($SourceConfigPath), $expectedSourceConfig, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw '提升执行器拒绝资产树之外的 source helper 或配置路径'
    }
    foreach ($requiredPath in @($PlanPath, $SourceHelperPath, $SourceConfigPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "提升执行器缺少文件: $requiredPath"
        }
    }
    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    if ([int]$plan.SchemaVersion -ne 1 -or [string]$plan.NetworkMode -notin @('Direct', 'China', 'Auto')) {
        throw '提升 plan schema 或 NetworkMode 无效'
    }

    foreach ($operation in @($plan.Operations)) {
        Assert-ElevatedOperation -Operation $operation
        $result = switch ([string]$operation.Type) {
            'WingetInstall' {
                $winget = (Get-Command winget.exe -ErrorAction Stop).Source
                $wingetArguments = @(
                    'install', '--id', [string]$operation.Id, '--exact', '--source', 'winget',
                    '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'
                )
                $helperArguments = @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SourceHelperPath,
                    '-Mode', [string]$plan.NetworkMode, '-Target', 'winget', '-ConfigPath', $SourceConfigPath,
                    '-FilePath', $winget, '-ArgumentList'
                ) + $wingetArguments + @('-OutputFormat', 'Text')
                Invoke-ElevatedProcess -Name ([string]$operation.Name) -FilePath powershell.exe -ArgumentList $helperArguments
            }
            'MsiInstall' {
                Invoke-ElevatedProcess -Name PowerShell -FilePath msiexec.exe -ArgumentList @(
                    '/package', [string]$operation.Path, '/quiet', '/norestart', 'ADD_PATH=1', 'USE_MU=1', 'ENABLE_MU=1'
                )
            }
            'ExeInstaller' {
                $arguments = if ([string]$operation.Name -eq 'Git') {
                    @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-')
                }
                else {
                    @('/silent')
                }
                Invoke-ElevatedProcess -Name ([string]$operation.Name) -FilePath ([string]$operation.Path) -ArgumentList $arguments
            }
            'WslInstall' {
                Invoke-ElevatedProcess -Name Wsl -FilePath wsl.exe -ArgumentList @('--install', '--no-launch', '-d', [string]$operation.Distribution)
            }
        }
        $results.Add($result)
        if ($result.Status -ne 'Succeeded') {
            break
        }
    }
    $exitCode = if (@($results | Where-Object Status -eq 'Failed').Count -gt 0) { 1 } elseif (@($results | Where-Object Status -eq 'RestartRequired').Count -gt 0) { 10 } else { 0 }
    $document = [pscustomobject]@{
        SchemaVersion = 1
        Status        = if ($exitCode -eq 1) { 'Failed' } elseif ($exitCode -eq 10) { 'RestartRequired' } else { 'Succeeded' }
        ExitCode      = $exitCode
        Results       = $results.ToArray()
    }
}
catch {
    $document = [pscustomobject]@{
        SchemaVersion = 1
        Status        = 'Failed'
        ExitCode      = 1
        Message       = $_.Exception.Message
        Results       = $results.ToArray()
    }
}

$resultDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ResultPath))
if (-not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
}
$document | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
exit ([int]$document.ExitCode)
