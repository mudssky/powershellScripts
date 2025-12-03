#!/usr/bin/env pwsh

<#
.SYNOPSIS
    脚本简短摘要（例如：跨平台自动化部署脚本）。

.DESCRIPTION
    详细描述脚本的功能。此处可以写多行。
    该脚本演示了编写跨平台 PowerShell 的标准结构。

.PARAMETER TargetPath
    目标路径参数说明。默认值为当前路径。

.PARAMETER Force
    开关参数。如果指定，将强制执行操作。

.EXAMPLE
    # Linux/macOS
    ./script-template.ps1 -TargetPath "/tmp/output" -Verbose

.EXAMPLE
    # Windows
    .\script-template.ps1 -TargetPath "C:\Temp" -Force
#>

# 1. 启用高级函数特性 (支持 -Verbose, -Debug, -WhatIf 等)
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "指定目标处理目录")]
    [string]$TargetPath = $PWD,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# 2. 设置严格的错误处理模式
# Latest: 禁止使用未初始化的变量，禁止调用不存在的属性
Set-StrictMode -Version Latest
# Stop: 遇到任何错误立即停止脚本执行
$ErrorActionPreference = 'Stop'

# 3. 定义主逻辑函数 (保持全局作用域整洁)
function Main {
    try {
        Write-Verbose "脚本启动..."
        
        # --- 跨平台路径处理 ---
        # 始终使用 Join-Path，不要手动拼接 "/" 或 "\"
        $ConfigFile = Join-Path $PSScriptRoot "config" "settings.json"
        
        # 规范化用户输入的路径
        $ResolvedPath = $TargetPath
        if (Test-Path $TargetPath) {
            $ResolvedPath = Convert-Path $TargetPath
        }
        Write-Verbose "目标路径: $ResolvedPath"
        Write-Verbose "配置文件路径 (预期): $ConfigFile"

        # --- 操作系统检测逻辑 ---
        if ($IsLinux) {
            Write-Verbose "检测到操作系统: Linux"
            # Linux 特有逻辑...
        }
        elseif ($IsMacOS) {
            Write-Verbose "检测到操作系统: macOS"
            # macOS 特有逻辑...
        }
        elseif ($IsWindows) {
            Write-Verbose "检测到操作系统: Windows"
            # Windows 特有逻辑...
        }

        # --- 核心业务逻辑示例 ---
        # 使用 SupportsShouldProcess 实现 -WhatIf 支持
        if ($PSCmdlet.ShouldProcess($ResolvedPath, "执行清理操作")) {
            
            # 模拟操作
            if ($Force) {
                Write-Host "正在强制处理 [$ResolvedPath] ..." -ForegroundColor Yellow
            }
            else {
                Write-Host "正在正常处理 [$ResolvedPath] ..." -ForegroundColor Cyan
            }
            
            # 模拟工作负载
            Start-Sleep -Milliseconds 500
            
            Write-Host "操作完成。" -ForegroundColor Green
        }
    }
    catch {
        # 捕获并美化错误输出
        Write-Error "发生严重错误: $($_.Exception.Message)"
        # 返回非零状态码，便于 CI/CD 管道检测失败
        exit 1
    }
    finally {
        Write-Verbose "脚本执行结束 (清理资源...)"
    }
}

# 4. 执行主函数
Main