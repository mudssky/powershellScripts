Set-StrictMode -Version Latest

function New-WindowsBootstrapResult {
    <#
    .SYNOPSIS
        创建 Windows Stage 0 结构化结果。

    .PARAMETER Name
        组件名称。

    .PARAMETER Status
        组件状态。

    .PARAMETER Message
        可操作结果摘要。

    .PARAMETER ExitCode
        组件退出码。

    .OUTPUTS
        PSCustomObject。包含 Name、Status、Message 和 ExitCode。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Skipped', 'Failed', 'Blocked', 'RestartRequired')]
        [string]$Status,

        [string]$Message = '',

        [int]$ExitCode = 0
    )

    return [pscustomobject]@{
        Name     = $Name
        Status   = $Status
        Message  = $Message
        ExitCode = $ExitCode
    }
}

function Get-WindowsBootstrapExitCode {
    <#
    .SYNOPSIS
        汇总 Windows Stage 0 组件退出码。

    .PARAMETER Result
        Stage 0 结果数组。

    .OUTPUTS
        System.Int32。Failed 返回 1，Blocked/RestartRequired 返回 10，其余返回 0。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Result
    )

    if (@($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
        return 1
    }
    if (@($Result | Where-Object { $_.Status -in @('Blocked', 'RestartRequired') }).Count -gt 0) {
        return 10
    }
    return 0
}

function Import-WindowsBootstrapCatalog {
    <#
    .SYNOPSIS
        使用 Windows PowerShell 5.1 data file loader 读取 Stage 0 声明。

    .PARAMETER Path
        windows-packages.psd1 路径。

    .OUTPUTS
        System.Collections.Hashtable。校验后的 Stage 0 清单。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $catalog = Import-PowerShellDataFile -LiteralPath ([System.IO.Path]::GetFullPath($Path))
    if ([int]$catalog.SchemaVersion -ne 1 -or -not $catalog.ContainsKey('Packages') -or
        -not $catalog.ContainsKey('Scoop') -or -not $catalog.ContainsKey('Wsl')) {
        throw 'Windows Stage 0 清单 schema 无效'
    }
    return $catalog
}

function Test-WindowsBootstrapAdministrator {
    <#
    .SYNOPSIS
        判断当前 Windows PowerShell 进程是否为管理员。

    .OUTPUTS
        System.Boolean。管理员进程返回 true。
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

function Update-WindowsBootstrapPath {
    <#
    .SYNOPSIS
        从 User、Machine 和 Process PATH 重建当前 Stage 0 进程环境。

    .OUTPUTS
        System.String。更新后的 PATH。
    #>
    [CmdletBinding()]
    param()

    $entries = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @(
            [Environment]::GetEnvironmentVariable('Path', 'User'),
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            $env:PATH
        )) {
        foreach ($entry in @([string]$source -split [System.IO.Path]::PathSeparator)) {
            $trimmed = ([string]$entry).Trim()
            if ($trimmed -and $seen.Add($trimmed)) {
                $entries.Add($trimmed)
            }
        }
    }
    $env:PATH = $entries -join [System.IO.Path]::PathSeparator
    return $env:PATH
}

function Test-WindowsInstallerSignature {
    <#
    .SYNOPSIS
        验证 Windows 安装包具有有效 Authenticode 签名。

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
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    return $signature.Status -eq 'Valid'
}

function Save-WindowsBootstrapReleaseAsset {
    <#
    .SYNOPSIS
        从官方 GitHub release 下载匹配的签名安装包。

    .PARAMETER ReleaseApi
        GitHub latest release API URL。

    .PARAMETER AssetPattern
        允许的安装包文件名正则。

    .PARAMETER DestinationDirectory
        下载目录。

    .OUTPUTS
        System.String。下载并验证后的绝对安装包路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string]$ReleaseApi,

        [Parameter(Mandatory)]
        [string]$AssetPattern,

        [Parameter(Mandatory)]
        [string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }
    $headers = @{ 'User-Agent' = 'powershellScripts-windows-bootstrap' }
    $release = Invoke-RestMethod -Uri $ReleaseApi -Headers $headers -UseBasicParsing
    $asset = @($release.assets | Where-Object { [string]$_.name -match $AssetPattern }) | Select-Object -First 1
    if ($null -eq $asset -or -not ([string]$asset.browser_download_url).StartsWith('https://')) {
        throw "官方 release 未找到匹配安装包: $AssetPattern"
    }
    $destination = Join-Path $DestinationDirectory ([string]$asset.name)
    Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -Headers $headers -UseBasicParsing -OutFile $destination
    if (-not (Test-WindowsInstallerSignature -Path $destination)) {
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        throw "安装包 Authenticode 签名无效: $($asset.name)"
    }
    return [System.IO.Path]::GetFullPath($destination)
}

function New-WindowsBootstrapOperation {
    <#
    .SYNOPSIS
        创建受限的 Windows 机器级 operation。

    .PARAMETER Type
        WingetInstall、MsiInstall、ExeInstaller 或 WslInstall。

    .PARAMETER Name
        Git、PowerShell、AutoHotkey 或 Wsl。

    .PARAMETER Id
        Winget 精确 package ID。

    .PARAMETER Path
        本地 MSI/EXE 安装包路径。

    .PARAMETER Distribution
        WSL 发行版名称。

    .OUTPUTS
        PSCustomObject。可序列化到受限提升 plan。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WingetInstall', 'MsiInstall', 'ExeInstaller', 'WslInstall')]
        [string]$Type,

        [Parameter(Mandatory)]
        [ValidateSet('Git', 'PowerShell', 'AutoHotkey', 'Wsl')]
        [string]$Name,

        [string]$Id = '',

        [string]$Path = '',

        [string]$Distribution = ''
    )

    return [pscustomobject][ordered]@{
        Type         = $Type
        Name         = $Name
        Id           = $Id
        Path         = $Path
        Distribution = $Distribution
    }
}

function Test-WindowsBootstrapComponentAvailable {
    <#
    .SYNOPSIS
        判断 Stage 0 机器组件是否已满足。

    .PARAMETER Name
        Git、PowerShell 或 AutoHotkey。

    .OUTPUTS
        System.Boolean。组件已可用时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Git', 'PowerShell', 'AutoHotkey')]
        [string]$Name
    )

    switch ($Name) {
        'Git' { return $null -ne (Get-Command git.exe -ErrorAction SilentlyContinue) -or $null -ne (Get-Command git -ErrorAction SilentlyContinue) }
        'PowerShell' { return $null -ne (Get-Command pwsh.exe -ErrorAction SilentlyContinue) -or $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue) }
        'AutoHotkey' {
            if (Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue) {
                return $true
            }
            foreach ($candidate in @(
                    'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
                    'C:\Program Files\AutoHotkey\AutoHotkey.exe',
                    'C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe'
                )) {
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $true
                }
            }
            return $false
        }
    }
}

function Resolve-WindowsBootstrapInstallOperation {
    <#
    .SYNOPSIS
        按本地安装包、winget、Direct 官方下载顺序解析机器安装 operation。

    .PARAMETER Name
        Git、PowerShell 或 AutoHotkey。

    .PARAMETER PackageConfig
        windows-packages.psd1 中对应的 package 声明。

    .PARAMETER LocalInstallerPath
        可选本地签名安装包。

    .PARAMETER NetworkMode
        Direct、China 或 Auto。

    .PARAMETER DownloadDirectory
        Direct fallback 下载目录。

    .PARAMETER Preview
        只生成计划，不下载或校验文件签名。

    .OUTPUTS
        PSCustomObject。包含 Result 和可选 Operation。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Git', 'PowerShell', 'AutoHotkey')]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [string]$LocalInstallerPath = '',

        [Parameter(Mandatory)]
        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$NetworkMode,

        [Parameter(Mandatory)]
        [string]$DownloadDirectory,

        [switch]$Preview
    )

    if (Test-WindowsBootstrapComponentAvailable -Name $Name) {
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status AlreadyPresent
            Operation = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalInstallerPath)) {
        $resolvedInstaller = [System.IO.Path]::GetFullPath($LocalInstallerPath)
        if (-not $Preview -and -not (Test-WindowsInstallerSignature -Path $resolvedInstaller)) {
            return [pscustomobject]@{
                Result    = New-WindowsBootstrapResult -Name $Name -Status Failed -Message "本地安装包签名无效: $resolvedInstaller" -ExitCode 1
                Operation = $null
            }
        }
        $operation = New-WindowsBootstrapOperation -Type ([string]$PackageConfig.InstallerType) -Name $Name -Path $resolvedInstaller
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status $(if ($Preview) { 'Preview' } else { 'Succeeded' }) -Message "使用本地安装包: $resolvedInstaller"
            Operation = $operation
        }
    }

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        if ($NetworkMode -ne 'Direct') {
            $sourceCmdletsReady = @(@('Get-WinGetSource', 'Add-WinGetSource', 'Remove-WinGetSource') | Where-Object {
                    $null -ne (Get-Command $_ -ErrorAction SilentlyContinue)
                }).Count -eq 3
            if (-not $sourceCmdletsReady) {
                return [pscustomobject]@{
                    Result    = New-WindowsBootstrapResult -Name $Name -Status Blocked -Message "$NetworkMode 缺少 Microsoft.WinGet.Client 结构化 source cmdlets" -ExitCode 10
                    Operation = $null
                }
            }
        }
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status $(if ($Preview) { 'Preview' } else { 'Succeeded' }) -Message "winget install $($PackageConfig.WingetId)"
            Operation = New-WindowsBootstrapOperation -Type WingetInstall -Name $Name -Id ([string]$PackageConfig.WingetId)
        }
    }

    if ($NetworkMode -ne 'Direct') {
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status Blocked -Message "$NetworkMode 缺少 winget adapter 或本地安装包" -ExitCode 10
            Operation = $null
        }
    }

    if ($Preview) {
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status Preview -Message "从 $($PackageConfig.ReleaseApi) 下载签名安装包"
            Operation = $null
        }
    }
    try {
        $installerPath = Save-WindowsBootstrapReleaseAsset `
            -ReleaseApi ([string]$PackageConfig.ReleaseApi) `
            -AssetPattern ([string]$PackageConfig.AssetPattern) `
            -DestinationDirectory $DownloadDirectory
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status Succeeded -Message "已准备官方安装包: $installerPath"
            Operation = New-WindowsBootstrapOperation -Type ([string]$PackageConfig.InstallerType) -Name $Name -Path $installerPath
        }
    }
    catch {
        return [pscustomobject]@{
            Result    = New-WindowsBootstrapResult -Name $Name -Status Failed -Message $_.Exception.Message -ExitCode 1
            Operation = $null
        }
    }
}

function ConvertTo-WindowsBootstrapQuotedArgument {
    <#
    .SYNOPSIS
        为 Start-Process Arguments 生成单个 Windows 命令行参数。

    .PARAMETER Value
        原始参数值。

    .OUTPUTS
        System.String。带必要双引号和转义的参数。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-WindowsBootstrapElevation {
    <#
    .SYNOPSIS
        使用最多一次 UAC 子进程执行受限机器 operation plan。

    .PARAMETER Operation
        New-WindowsBootstrapOperation 返回的 operation 数组。

    .PARAMETER NetworkMode
        Direct、China 或 Auto。

    .PARAMETER ExecutorPath
        固定提升执行脚本路径。

    .PARAMETER SourceHelperPath
        固定 winget Stage 0 source helper 路径。

    .PARAMETER SourceConfigPath
        固定 Stage 0 source 配置路径。

    .OUTPUTS
        PSCustomObject。提升子进程写回的结果文档。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Operation,

        [Parameter(Mandatory)]
        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$NetworkMode,

        [Parameter(Mandatory)]
        [string]$ExecutorPath,

        [Parameter(Mandatory)]
        [string]$SourceHelperPath,

        [Parameter(Mandatory)]
        [string]$SourceConfigPath
    )

    if (@($Operation).Count -eq 0) {
        return [pscustomobject]@{ SchemaVersion = 1; Status = 'Succeeded'; ExitCode = 0; Results = @() }
    }
    $stateDirectory = Join-Path $env:TEMP ("powershellScripts-windows-plan-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $planPath = Join-Path $stateDirectory 'plan.json'
    $resultPath = Join-Path $stateDirectory 'result.json'
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        NetworkMode   = $NetworkMode
        Operations    = @($Operation)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

    try {
        $argumentValues = @(
            '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ([System.IO.Path]::GetFullPath($ExecutorPath)),
            '-PlanPath', $planPath, '-ResultPath', $resultPath,
            '-SourceHelperPath', ([System.IO.Path]::GetFullPath($SourceHelperPath)),
            '-SourceConfigPath', ([System.IO.Path]::GetFullPath($SourceConfigPath))
        )
        $argumentString = @($argumentValues | ForEach-Object { ConvertTo-WindowsBootstrapQuotedArgument -Value ([string]$_) }) -join ' '
        try {
            $process = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argumentString -Wait -PassThru
        }
        catch {
            return [pscustomobject]@{ SchemaVersion = 1; Status = 'Blocked'; ExitCode = 10; Message = 'UAC 已取消或无法启动提升进程'; Results = @() }
        }
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            return [pscustomobject]@{ SchemaVersion = 1; Status = 'Blocked'; ExitCode = 10; Message = "提升进程未写回结果，exit=$($process.ExitCode)"; Results = @() }
        }
        return Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $stateDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function @(
    'New-WindowsBootstrapResult',
    'Get-WindowsBootstrapExitCode',
    'Import-WindowsBootstrapCatalog',
    'Test-WindowsBootstrapAdministrator',
    'Update-WindowsBootstrapPath',
    'Test-WindowsInstallerSignature',
    'Save-WindowsBootstrapReleaseAsset',
    'New-WindowsBootstrapOperation',
    'Test-WindowsBootstrapComponentAvailable',
    'Resolve-WindowsBootstrapInstallOperation',
    'Invoke-WindowsBootstrapElevation'
)
