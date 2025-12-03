#!/usr/bin/env pwsh

<#
.SYNOPSIS
    PowerShell脚本环境安装脚本

.DESCRIPTION
    该脚本用于安装和配置PowerShell脚本运行环境。包括检查管理员权限、
    安装测试框架和其他必要的依赖组件。脚本会自动检测权限并提示用户
    是否继续执行需要管理员权限的操作。

.EXAMPLE
    .\install.ps1
    运行安装脚本，配置PowerShell环境

.NOTES
    需要psutils模块支持
    某些操作可能需要管理员权限
    会检查并提示权限要求
    自动安装测试框架和相关组件
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Main {
    try {
        # 导入 psutils 模块以使用管理员权限检测功能
        $psutilsPath = Join-Path $PSScriptRoot 'psutils'
        Import-Module $psutilsPath -Force

        # 检查管理员权限
        if (-not (Test-Administrator)) {
            Write-Warning "检测到当前未以管理员权限运行"
            Write-Host "某些操作（如创建符号链接）可能需要管理员权限" -ForegroundColor Yellow
            Write-Host "如果遇到权限错误，请以管理员身份重新运行此脚本" -ForegroundColor Yellow

            # 询问用户是否继续
            $continue = Read-Host "是否继续执行脚本？(y/N)"
            if ($continue -notmatch '^[Yy]') {
                Write-Host "脚本已取消执行" -ForegroundColor Red
                exit 1
            }
        }
        else {
            Write-Host "已检测到管理员权限" -ForegroundColor Green
        }

        # 安装测试框架（副作用操作，支持 -WhatIf）
        if ($PSCmdlet.ShouldProcess('Pester 模块', '检查并安装')) {
            if (-not (Get-Module -ListAvailable -Name Pester)) {
                Write-Host "正在安装 Pester 模块..." -ForegroundColor Yellow
                Install-Module -Name Pester -Force
                Write-Host "Pester 模块安装完成" -ForegroundColor Green
            }
            else {
                Write-Host "Pester 模块已安装，跳过安装" -ForegroundColor Green
            }
        }

        # 根据平台加载 Profile（副作用操作，支持 -WhatIf）
        if ($IsWindows) {
            Write-Verbose "当前环境为 Windows，将执行 Windows 特定配置"
            if ($PSCmdlet.ShouldProcess('Windows Profile', '加载')) {
                & (Join-Path $PSScriptRoot 'profile' 'profile.ps1') -loadProfile
            }
        }
        else {
            Write-Verbose "当前环境为 Unix 或类 Unix 系统，将执行 Unix 特定配置"
            if ($PSCmdlet.ShouldProcess('Unix Profile', '加载')) {
                & (Join-Path $PSScriptRoot 'profile' 'profile_unix.ps1') -loadProfile
            }
        }
    }
    catch {
        Write-Error "执行安装流程发生错误: $($_.Exception.Message)"
        Write-Verbose "错误详情: $($_.Exception.ToString())"
        exit 1
    }
}

Main

