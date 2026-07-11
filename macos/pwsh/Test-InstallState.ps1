#!/usr/bin/env pwsh

<#
.SYNOPSIS
    为 macOS 只读验证入口提供应用清单和 Profile 工具检查。

.PARAMETER Step
    要检查的逻辑步骤：core-cli、fonts、full-apps 或 profile-tools。

.PARAMETER OutputFormat
    Tsv 供 zsh 逐行消费，Json 供独立诊断使用。

.OUTPUTS
    每项检查包含 Step、Status、Name 与 Message；内部错误时退出 1。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('core-cli', 'fonts', 'full-apps', 'profile-tools')]
    [string]$Step,

    [ValidateSet('Tsv', 'Json')]
    [string]$OutputFormat = 'Tsv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

function New-InstallStateResult {
    <#
    .SYNOPSIS
        创建统一的只读检查结果。

    .PARAMETER Step
        逻辑步骤 ID。

    .PARAMETER Status
        Pass、Warn、Fail 或 Blocked。

    .PARAMETER Name
        检查项名称。

    .PARAMETER Message
        检查摘要。

    .OUTPUTS
        PSCustomObject。包含 Step、Status、Name 与 Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warn', 'Fail', 'Blocked')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Message = ''
    )

    return [pscustomobject]@{
        Step    = $Step
        Status  = $Status
        Name    = $Name
        Message = $Message
    }
}

function Get-CatalogInstallState {
    <#
    .SYNOPSIS
        从统一应用清单检查指定预设类别的安装状态。

    .PARAMETER Step
        逻辑步骤 ID。

    .OUTPUTS
        PSCustomObject[]。逐应用返回 Pass、Warn 或 Fail。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('core-cli', 'fonts', 'full-apps')]
        [string]$Step
    )

    Import-Module (Join-Path $repoRoot 'psutils') -Force
    Import-Module (Join-Path $repoRoot 'psutils/modules/test.psm1') -Force
    $configPath = Join-Path $repoRoot 'profile/installer/apps-config.json'
    $config = (Resolve-ConfigSources -Sources @(
            @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = $configPath }
        ) -BasePath $repoRoot -ErrorOnMissing).Values
    $null = Test-PackageManagerAppCatalog -ConfigObject $config

    $packageManagers = ConvertTo-ConfigHashtable -InputObject $config.packageManagers
    $selectionParameters = @{
        Apps           = @($packageManagers.homebrew)
        TargetOS       = 'macOS'
        IncludeSkipped = $true
    }
    switch ($Step) {
        'core-cli' {
            $selectionParameters.RequiredTag = @('core', 'cli')
        }
        'fonts' {
            $selectionParameters.RequiredTag = @('core', 'font')
        }
        'full-apps' {
            $selectionParameters.RequiredTag = @('full')
            $selectionParameters.AnyTag = @('gui', 'platform')
        }
    }

    $selectedApps = @(Select-PackageManagerApps @selectionParameters)
    if ($selectedApps.Count -eq 0) {
        return @(New-InstallStateResult -Step $Step -Status Fail -Name catalog -Message '应用清单没有匹配项')
    }

    return @($selectedApps | ForEach-Object {
            $app = ConvertTo-ConfigHashtable -InputObject $_
            if ($app.ContainsKey('skipInstall') -and [bool]$app.skipInstall) {
                New-InstallStateResult -Step $Step -Status Warn -Name ([string]$app.name) -Message '配置标记 skipInstall'
            }
            else {
                $appName = if ($app.ContainsKey('cliName') -and $app.cliName) { [string]$app.cliName } else { [string]$app.name }
                $filterCli = $app.ContainsKey('filterCli') -and [bool]$app.filterCli
                $installed = Test-ApplicationInstalled -AppName $appName -FilterCli:$filterCli
                New-InstallStateResult `
                    -Step $Step `
                    -Status $(if ($installed) { 'Pass' } else { 'Fail' }) `
                    -Name ([string]$app.name) `
                    -Message $(if ($installed) { '已安装' } else { '未检测到安装结果' })
            }
        })
}

function Get-ProfileToolsInstallState {
    <#
    .SYNOPSIS
        检查 Profile、模块、运行时、bin 和仓库构建产物。

    .OUTPUTS
        PSCustomObject[]。逐组件返回 Pass 或 Fail。
    #>
    [CmdletBinding()]
    param()

    Import-Module (Join-Path $repoRoot 'psutils') -Force
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($moduleName in @('Pester', 'PSReadLine')) {
        $installed = Test-ModuleInstalled -ModuleName $moduleName
        $results.Add((New-InstallStateResult `
                    -Step profile-tools `
                    -Status $(if ($installed) { 'Pass' } else { 'Fail' }) `
                    -Name "module:$moduleName" `
                    -Message $(if ($installed) { '模块可用' } else { '模块不可用' })))
    }

    $profilePath = [string]$PROFILE
    $expectedProfileContent = ". `"$(Join-Path $repoRoot 'profile/profile.ps1')`""
    $profileMatches = if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        (Get-Content -LiteralPath $profilePath -Raw).TrimEnd("`r", "`n") -eq $expectedProfileContent
    }
    else {
        $false
    }
    $results.Add((New-InstallStateResult `
                -Step profile-tools `
                -Status $(if ($profileMatches) { 'Pass' } else { 'Fail' }) `
                -Name profile `
                -Message $(if ($profileMatches) { 'Profile 指向统一入口' } else { "Profile 未指向统一入口: $profilePath" })))

    foreach ($commandName in @('node', 'pnpm', 'nbstripout')) {
        $available = $null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)
        $results.Add((New-InstallStateResult `
                    -Step profile-tools `
                    -Status $(if ($available) { 'Pass' } else { 'Fail' }) `
                    -Name "command:$commandName" `
                    -Message $(if ($available) { '命令可用' } else { '命令不可用' })))
    }

    $pathChecks = [ordered]@{
        'bin-directory' = Join-Path $repoRoot 'bin'
        'bash-artifact' = Join-Path $repoRoot 'bin/aliyun-oss-put'
        'node-artifact' = Join-Path $repoRoot 'scripts/node/dist/rule-loader.cjs'
        'node-shim'     = Join-Path $repoRoot 'bin/rule-loader'
    }
    foreach ($entry in $pathChecks.GetEnumerator()) {
        $exists = Test-Path -LiteralPath $entry.Value
        $results.Add((New-InstallStateResult `
                    -Step profile-tools `
                    -Status $(if ($exists) { 'Pass' } else { 'Fail' }) `
                    -Name $entry.Key `
                    -Message $(if ($exists) { "存在: $($entry.Value)" } else { "缺失: $($entry.Value)" })))
    }

    return $results.ToArray()
}

try {
    $results = if ($Step -eq 'profile-tools') {
        @(Get-ProfileToolsInstallState)
    }
    else {
        @(Get-CatalogInstallState -Step $Step)
    }

    if ($OutputFormat -eq 'Json') {
        Write-Output ($results | ConvertTo-Json -Depth 6)
    }
    else {
        foreach ($result in $results) {
            $message = ([string]$result.Message) -replace "[`t`r`n]+", ' '
            Write-Output ("{0}`t{1}`t{2}" -f $result.Status, $result.Name, $message)
        }
    }
    exit 0
}
catch {
    $failure = New-InstallStateResult -Step $Step -Status Fail -Name internal -Message $_.Exception.Message
    if ($OutputFormat -eq 'Json') {
        Write-Output ($failure | ConvertTo-Json -Depth 4)
    }
    else {
        $message = ([string]$failure.Message) -replace "[`t`r`n]+", ' '
        Write-Output ("Fail`tinternal`t{0}" -f $message)
    }
    exit 1
}
