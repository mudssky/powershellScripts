#!/usr/bin/env pwsh

<#
.SYNOPSIS
    测试 lint-staged 的文件
.DESCRIPTION
    简单列出当前 PowerShell 进程数量用于 lint-staged 验证。
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Function {
    $result = Get-Process | Where-Object { $_.Name -eq 'powershell' }
    return $result
}

$processes = Test-Function
Write-Host "找到 $($processes.Count) 个进程"
