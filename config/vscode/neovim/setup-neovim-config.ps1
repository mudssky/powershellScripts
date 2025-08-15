<#
.SYNOPSIS
    为VSCode Neovim扩展设置配置文件软连接

.DESCRIPTION
    此脚本创建软连接，将自定义的Neovim配置文件链接到标准的Neovim配置目录，
    使VSCode Neovim扩展能够使用我们的配置。

.PARAMETER Force
    强制覆盖已存在的配置文件

.EXAMPLE
    .\setup-neovim-config.ps1
    创建Neovim配置软连接

.EXAMPLE
    .\setup-neovim-config.ps1 -Force
    强制创建软连接，覆盖已存在的文件

.NOTES
    作者: mudssky
    需要管理员权限来创建软连接
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = "强制覆盖已存在的配置文件")]
    [switch]$Force
)

# 获取脚本所在目录
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 源配置文件路径
$sourceConfigPath = Join-Path $scriptRoot "vscode_init.lua"

# Neovim配置目录路径
$neovimConfigDir = Join-Path $env:LOCALAPPDATA "nvim"
$targetConfigPath = Join-Path $neovimConfigDir "init.lua"

# 检查源文件是否存在
if (-not (Test-Path $sourceConfigPath)) {
    Write-Error "源配置文件不存在: $sourceConfigPath"
    exit 1
}

Write-Host "正在设置Neovim配置..." -ForegroundColor Green
Write-Host "源文件: $sourceConfigPath" -ForegroundColor Cyan
Write-Host "目标位置: $targetConfigPath" -ForegroundColor Cyan

try {
    # 创建Neovim配置目录（如果不存在）
    if (-not (Test-Path $neovimConfigDir)) {
        Write-Host "创建Neovim配置目录: $neovimConfigDir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $neovimConfigDir -Force | Out-Null
    }

    # 检查目标文件是否已存在
    if (Test-Path $targetConfigPath) {
        if ($Force) {
            Write-Warning "目标文件已存在，将被覆盖: $targetConfigPath"
            Remove-Item $targetConfigPath -Force
        } else {
            Write-Warning "目标文件已存在: $targetConfigPath"
            $response = Read-Host "是否覆盖? (y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-Host "操作已取消" -ForegroundColor Yellow
                exit 0
            }
            Remove-Item $targetConfigPath -Force
        }
    }

    # 创建软连接
    if ($PSCmdlet.ShouldProcess($targetConfigPath, "创建软连接")) {
        Write-Host "创建软连接..." -ForegroundColor Yellow
        
        # 检查是否有管理员权限
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Warning "需要管理员权限来创建软连接"
            Write-Host "正在以管理员权限重新启动脚本..." -ForegroundColor Yellow
            
            $arguments = "-File `"$($MyInvocation.MyCommand.Path)`""
            if ($Force) {
                $arguments += " -Force"
            }
            
            Start-Process pwsh -ArgumentList $arguments -Verb RunAs -Wait
            exit 0
        }
        
        # 使用cmd的mklink命令创建软连接
        $mklinkCommand = "mklink `"$targetConfigPath`" `"$sourceConfigPath`""
        $result = cmd /c $mklinkCommand 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 软连接创建成功!" -ForegroundColor Green
            Write-Host "Neovim配置已链接到: $targetConfigPath" -ForegroundColor Green
        } else {
            Write-Error "创建软连接失败: $result"
            exit 1
        }
    }

    # 验证软连接
    if (Test-Path $targetConfigPath) {
        $linkTarget = (Get-Item $targetConfigPath).Target
        if ($linkTarget) {
            Write-Host "✅ 验证成功: 软连接指向 $linkTarget" -ForegroundColor Green
        } else {
            Write-Host "✅ 配置文件已存在: $targetConfigPath" -ForegroundColor Green
        }
    } else {
        Write-Error "验证失败: 目标文件不存在"
        exit 1
    }

    Write-Host "`n🎉 Neovim配置设置完成!" -ForegroundColor Green
    Write-Host "现在可以在VSCode中使用Neovim扩展了" -ForegroundColor Cyan
    
} catch {
    Write-Error "设置过程中发生错误: $($_.Exception.Message)"
    exit 1
}