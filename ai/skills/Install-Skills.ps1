#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按配置同步安装 agent skills 与配套工具。

.DESCRIPTION
    读取 `skills.config.json`，生成 skills CLI 安装计划，并调用 `npx skills add`
    将远程或本地开发 skill 安装到指定 agent。脚本同时支持配置 tool setup，
    用于 Context7 这类不是通过 `skills add` 安装的工具。

.PARAMETER ConfigPath
    JSON 配置文件路径；默认读取脚本目录下的 `skills.config.json`。

.PARAMETER Agent
    覆盖配置中的默认 agent 列表；支持 `claude`、`codex` 等友好名称。

.PARAMETER Name
    只处理指定 skill 或 tool 名称；未指定时处理配置中的全部项目。

.PARAMETER IncludeDevAll
    自动发现 `dev/*/SKILL.md` 并把未显式配置的本地开发 skill 纳入安装计划。

.PARAMETER DryRun
    只展示安装计划，不执行外部命令。

.PARAMETER Yes
    跳过脚本级安装计划确认，适合多设备同步或 CI 场景。

.PARAMETER Force
    明确表示即使目标可能已存在也继续执行安装命令；实际覆盖语义由 CLI 决定。

.PARAMETER LogDirectory
    覆盖本次运行日志目录；默认写入 `ai/skills/logs`。
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$ConfigPath = '',

    [Alias('Agents')]
    [string[]]$Agent = @(),

    [Alias('SkillName')]
    [string[]]$Name = @(),

    [switch]$IncludeDevAll,

    [switch]$DryRun,

    [switch]$Yes,

    [switch]$Force,

    [string]$LogDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SkillsInstallerRoot = $PSScriptRoot
$script:SkillsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:SkillsInstallerRoot '..' '..'))

$skillsProcessModulePath = Join-Path $script:SkillsRepoRoot 'psutils/modules/process.psm1'
if (-not (Test-Path -LiteralPath $skillsProcessModulePath -PathType Leaf)) {
    throw "未找到共享命令执行模块: $skillsProcessModulePath"
}
Import-Module $skillsProcessModulePath -Force

$skillsConfigModulePath = Join-Path $script:SkillsRepoRoot 'psutils/modules/config.psm1'
if (-not (Test-Path -LiteralPath $skillsConfigModulePath -PathType Leaf)) {
    throw "未找到共享配置解析器模块: $skillsConfigModulePath"
}
Import-Module $skillsConfigModulePath -Force

$skillsPrivateScripts = @(
    'bootstrap.ps1'
    'plan.ps1'
    'presentation.ps1'
    'execution.ps1'
)
foreach ($privateScript in $skillsPrivateScripts) {
    $privateScriptPath = Join-Path $script:SkillsInstallerRoot (Join-Path 'private' $privateScript)
    if (-not (Test-Path -LiteralPath $privateScriptPath -PathType Leaf)) {
        throw "未找到 skills 安装器私有脚本: $privateScriptPath"
    }

    . $privateScriptPath
}

function Invoke-SkillsInstallMain {
    <#
    .SYNOPSIS
        skills 安装器主入口。

    .PARAMETER ConfigPath
        JSON 配置文件路径。

    .PARAMETER Agent
        CLI 传入的 agent 覆盖列表。

    .PARAMETER Name
        只处理指定 skill 或 tool 名称。

    .PARAMETER IncludeDevAll
        是否自动发现 dev 目录下全部本地 skill。

    .PARAMETER DryRun
        是否只展示计划。

    .PARAMETER Yes
        是否跳过计划确认。

    .PARAMETER Force
        是否明确继续执行安装命令。

    .PARAMETER LogDirectory
        日志目录。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .OUTPUTS
        int。进程退出码。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [AllowEmptyString()]
        [string]$ConfigPath = '',

        [string[]]$Agent = @(),

        [string[]]$Name = @(),

        [switch]$IncludeDevAll,

        [switch]$DryRun,

        [switch]$Yes,

        [switch]$Force,

        [AllowEmptyString()]
        [string]$LogDirectory = '',

        [scriptblock]$CommandRunner = {
            param(
                [string]$Command,
                [string[]]$Arguments,
                [string]$WorkingDirectory,
                [string]$LogPath,
                [bool]$AllowFailure,
                [bool]$SuppressOutput
            )
            Invoke-NativeCommand -Command $Command -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -LogPath $LogPath -AllowFailure:$AllowFailure -SuppressOutput:$SuppressOutput
        }
    )

    $cliParameters = @{}
    if ($Agent.Count -gt 0) {
        $cliParameters['Agent'] = $Agent
    }

    $config = Read-SkillsInstallerConfig -ConfigPath $ConfigPath -CliParameters $cliParameters
    $plan = New-SkillsPlanFromConfig -Config $config -OverrideAgents $Agent -Name $Name -IncludeDevAll:$IncludeDevAll

    if ($DryRun) {
        Show-SkillsInstallPlan -Plan $plan
        return 0
    }

    if ($WhatIfPreference) {
        Invoke-SkillsInstallPlan -Plan $plan -LogPath '' -CommandRunner $CommandRunner -Force:$Force
        return 0
    }

    $effectiveLogDirectory = if ([string]::IsNullOrWhiteSpace($LogDirectory)) { Resolve-SkillsDefaultLogDirectory } else { $LogDirectory }
    $logPath = New-CommandLogFile -LogDirectory $effectiveLogDirectory -Prefix 'skills-install'
    Write-Host "日志: $logPath"
    Write-CommandLogLine -LogPath $logPath -Message "CONFIG $($config.Path)"
    Write-CommandLogLine -LogPath $logPath -Message "FORCE $([bool]$Force)"

    $pendingPlan = if ($Force) {
        $plan
    }
    else {
        Get-SkillsPendingPlan -Plan $plan -LogPath $logPath -CommandRunner $CommandRunner
    }
    Show-SkillsInstallPlan -Plan $pendingPlan
    if ($pendingPlan.Steps.Count -eq 0) {
        return 0
    }

    if (-not (Confirm-SkillsInstallPlan -Plan $pendingPlan -Yes:$Yes)) {
        Write-Host '已取消。'
        return 0
    }

    Invoke-SkillsInstallPlan -Plan $pendingPlan -LogPath $logPath -CommandRunner $CommandRunner -Force:$Force
    return 0
}

if ($env:SKILLS_INSTALLER_SKIP_MAIN -ne '1') {
    try {
        exit (Invoke-SkillsInstallMain `
                -ConfigPath $ConfigPath `
                -Agent $Agent `
                -Name $Name `
                -IncludeDevAll:$IncludeDevAll `
                -DryRun:$DryRun `
                -Yes:$Yes `
                -Force:$Force `
                -LogDirectory $LogDirectory)
    }
    catch {
        Write-Error $_
        exit 1
    }
}

