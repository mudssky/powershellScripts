#!/usr/bin/env pwsh

<#
.SYNOPSIS
    PowerShell代码静态分析工具

.DESCRIPTION
    该脚本使用PSScriptAnalyzer模块对PowerShell代码进行静态分析和代码质量检查。
    支持自定义配置文件和安装PSScriptAnalyzer模块。

.PARAMETER Path
    要分析的代码路径，默认为当前目录。支持递归分析子目录

.PARAMETER ConfigPath
    分析器配置文件路径，默认为脚本目录下的.vscode\analyzersettings.psd1

.PARAMETER Install
    开关参数，如果指定则安装PSScriptAnalyzer模块后退出

.EXAMPLE
    .\pslint.ps1
    分析当前目录下的所有PowerShell文件

.EXAMPLE
    .\pslint.ps1 -Path "C:\Scripts"
    分析指定目录下的PowerShell文件

.EXAMPLE
    .\pslint.ps1 -Install
    安装PSScriptAnalyzer模块

.NOTES
    需要PSScriptAnalyzer模块
    使用自定义配置文件进行代码分析
    支持递归分析目录结构
#>
param(
    [string]$Path = '.',
    [string]$ConfigPath = "$PSScriptRoot\.vscode\analyzersettings.psd1",
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Install) {
    Install-Module PSScriptAnalyzer -Force
    exit
}



Invoke-ScriptAnalyzer -Recurse -Path $Path -Profile $ConfigPath
