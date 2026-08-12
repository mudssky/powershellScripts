#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装仓库固定版本的 Pester。

.PARAMETER Scope
    PowerShell 模块安装范围。

.PARAMETER Version
    要安装的精确 Pester 版本。未指定时读取仓库 `.pester-version`。

.OUTPUTS
    None。安装失败时抛出异常。
#>
[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
$versionPath = Join-Path $repoRoot '.pester-version'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "缺少 Pester 版本配置: $versionPath"
}

$pesterVersion = if ([string]::IsNullOrWhiteSpace($Version)) {
    (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    $Version.Trim()
}
if ($pesterVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Pester 版本格式无效: $pesterVersion"
}

if (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.ToString() -eq $pesterVersion }) {
    return
}

Install-PSResource -Name Pester -Version $pesterVersion -Scope $Scope -TrustRepository -ErrorAction Stop
