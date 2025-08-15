<#
.SYNOPSIS
    VSCode Neovim 配置文件安装脚本

.DESCRIPTION
    此脚本用于安装和配置 VSCode Neovim 插件的配置文件。主要功能包括：
    - 创建 Neovim 配置目录
    - 通过软链接方式链接配置文件
    - 自动权限提升
    - 配置验证和测试
    - 插件依赖检查

.PARAMETER SourceConfig
    源配置文件的路径。默认为当前目录下的 vscode_init.lua

.PARAMETER TargetDir
    目标配置目录。默认为 $env:LOCALAPPDATA\nvim

.PARAMETER Force
    如果目标文件已存在，是否强制覆盖

.PARAMETER Verify
    安装后验证配置文件语法

.PARAMETER InstallPlugins
    是否自动安装插件依赖

.EXAMPLE
    .\setup-neovim-config.ps1
    使用默认参数创建软链接

.EXAMPLE
    .\setup-neovim-config.ps1 -Force -Verify
    强制覆盖现有配置并验证语法

.EXAMPLE
    .\setup-neovim-config.ps1 -SourceConfig "custom_config.lua" -InstallPlugins
    使用自定义配置文件并安装插件

.NOTES
    作者: mudssky
    版本: 2.0
    更新: 2024
    
    要求:
    - Windows PowerShell 5.1+ 或 PowerShell 7+
    - Neovim 0.8+
    - VSCode Neovim 插件
    
    功能:
    - 自动权限检测和提升
    - 配置文件语法验证
    - 插件依赖管理
    - 详细的状态报告
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = "源配置文件路径")]
    [string]$SourceConfig = "vscode_init.lua",
    
    [Parameter(HelpMessage = "目标配置目录")]
    [string]$TargetDir = "$env:LOCALAPPDATA\nvim",
    
    [Parameter(HelpMessage = "强制覆盖现有文件")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "验证配置文件语法")]
    [switch]$Verify,
    
    [Parameter(HelpMessage = "自动安装插件依赖")]
    [switch]$InstallPlugins
)

# =============================================
# 辅助函数
# =============================================

function Test-Administrator {
    <#
    .SYNOPSIS
        检查当前是否以管理员权限运行
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedProcess {
    <#
    .SYNOPSIS
        以管理员权限重新启动脚本
    #>
    param(
        [string]$ScriptPath,
        [string]$Arguments
    )
    
    Write-Host "🔐 需要管理员权限来创建软链接..." -ForegroundColor Yellow
    Write-Host "正在请求权限提升..." -ForegroundColor Cyan
    
    try {
        Start-Process -FilePath "pwsh" -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments" -Verb RunAs -Wait
        return $true
    }
    catch {
        Write-Error "❌ 权限提升失败: $($_.Exception.Message)"
        return $false
    }
}

function Test-NeovimInstallation {
    <#
    .SYNOPSIS
        检查 Neovim 是否已安装
    #>
    try {
        $nvimVersion = nvim --version 2>$null | Select-Object -First 1
        if ($nvimVersion -match "NVIM v([0-9.]+)") {
            Write-Host "✅ 检测到 Neovim 版本: $($matches[1])" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Warning "⚠️  未检测到 Neovim 安装"
        Write-Host "请先安装 Neovim:" -ForegroundColor Yellow
        Write-Host "  choco install neovim" -ForegroundColor Cyan
        Write-Host "  scoop install neovim" -ForegroundColor Cyan
        Write-Host "  winget install Neovim.Neovim" -ForegroundColor Cyan
        return $false
    }
    return $false
}

function Test-ConfigSyntax {
    <#
    .SYNOPSIS
        验证 Lua 配置文件语法
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    Write-Host "🔍 验证配置文件语法..." -ForegroundColor Cyan
    
    try {
        $result = nvim --headless -c "luafile $ConfigPath" -c "qa" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 配置文件语法正确" -ForegroundColor Green
            return $true
        }
        else {
            Write-Error "❌ 配置文件语法错误:"
            Write-Host $result -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Error "❌ 无法验证配置文件: $($_.Exception.Message)"
        return $false
    }
}

function Install-LazyNvim {
    <#
    .SYNOPSIS
        安装 lazy.nvim 插件管理器
    #>
    $lazyPath = "$env:LOCALAPPDATA\nvim-data\lazy\lazy.nvim"
    
    if (Test-Path $lazyPath) {
        Write-Host "✅ lazy.nvim 已安装" -ForegroundColor Green
        return $true
    }
    
    Write-Host "📦 安装 lazy.nvim 插件管理器..." -ForegroundColor Cyan
    
    try {
        git clone --filter=blob:none --branch=stable https://github.com/folke/lazy.nvim.git $lazyPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ lazy.nvim 安装成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-Error "❌ lazy.nvim 安装失败"
            return $false
        }
    }
    catch {
        Write-Error "❌ 安装 lazy.nvim 时出错: $($_.Exception.Message)"
        return $false
    }
}

function Install-Plugins {
    <#
    .SYNOPSIS
        安装配置文件中定义的插件
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    Write-Host "📦 安装插件依赖..." -ForegroundColor Cyan
    
    try {
        # 使用 Neovim 的 headless 模式安装插件
        $result = nvim --headless -c "luafile $ConfigPath" -c "Lazy! sync" -c "qa" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 插件安装完成" -ForegroundColor Green
            return $true
        }
        else {
            Write-Warning "⚠️  插件安装可能遇到问题:"
            Write-Host $result -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Error "❌ 插件安装失败: $($_.Exception.Message)"
        return $false
    }
}

# =============================================
# 主脚本逻辑
# =============================================

# 获取脚本所在目录
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 设置源文件和目标路径
$sourceConfigPath = if ([System.IO.Path]::IsPathRooted($SourceConfig)) {
    $SourceConfig
} else {
    Join-Path $scriptRoot $SourceConfig
}
$targetConfigPath = Join-Path $TargetDir "init.lua"

Write-Host "=== VSCode Neovim 配置安装脚本 v2.0 ===" -ForegroundColor Cyan
Write-Host "作者: mudssky" -ForegroundColor Gray
Write-Host ""

# 显示配置信息
Write-Host "📋 配置信息:" -ForegroundColor Cyan
Write-Host "  源文件: $sourceConfigPath" -ForegroundColor Gray
Write-Host "  目标目录: $TargetDir" -ForegroundColor Gray
Write-Host "  目标文件: $targetConfigPath" -ForegroundColor Gray
Write-Host "  强制覆盖: $Force" -ForegroundColor Gray
Write-Host "  验证语法: $Verify" -ForegroundColor Gray
Write-Host "  安装插件: $InstallPlugins" -ForegroundColor Gray
Write-Host ""

# =============================================
# 前置检查
# =============================================

Write-Host "🔍 执行前置检查..." -ForegroundColor Cyan

# 检查源文件是否存在
if (-not (Test-Path $sourceConfigPath)) {
    Write-Error "❌ 源配置文件不存在: $sourceConfigPath"
    Write-Host "请确保配置文件路径正确" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ 源配置文件存在" -ForegroundColor Green

# 检查 Neovim 安装
if (-not (Test-NeovimInstallation)) {
    exit 1
}

# 检查管理员权限
if (-not (Test-Administrator)) {
    # 构建参数字符串
    $arguments = "-SourceConfig '$SourceConfig' -TargetDir '$TargetDir'"
    if ($Force) { $arguments += " -Force" }
    if ($Verify) { $arguments += " -Verify" }
    if ($InstallPlugins) { $arguments += " -InstallPlugins" }
    
    if (Start-ElevatedProcess -ScriptPath $MyInvocation.MyCommand.Path -Arguments $arguments) {
        Write-Host "✅ 脚本执行完成" -ForegroundColor Green
        exit 0
    } else {
        exit 1
    }
}

Write-Host "✅ 权限检查通过" -ForegroundColor Green
Write-Host ""

# =============================================
# 配置文件安装
# =============================================

Write-Host "📦 开始安装配置..." -ForegroundColor Cyan

# 创建目标目录
if (-not (Test-Path $TargetDir)) {
    Write-Host "📁 创建配置目录: $TargetDir" -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        Write-Host "✅ 目录创建成功" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ 创建目录失败: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "✅ 目标目录已存在" -ForegroundColor Green
}

# 处理现有配置文件
if (Test-Path $targetConfigPath) {
    if ($Force) {
        Write-Host "⚠️  目标文件已存在，将被覆盖" -ForegroundColor Yellow
        Remove-Item $targetConfigPath -Force
    } else {
        Write-Host "⚠️  目标文件已存在: $targetConfigPath" -ForegroundColor Yellow
        $response = Read-Host "是否覆盖现有文件? (y/N)"
        if ($response -notmatch '^[Yy]') {
            Write-Host "❌ 操作已取消" -ForegroundColor Red
            exit 1
        }
        Remove-Item $targetConfigPath -Force
    }
}

# 创建软链接
Write-Host "🔗 创建软链接..." -ForegroundColor Cyan
try {
    New-Item -ItemType SymbolicLink -Path $targetConfigPath -Target $sourceConfigPath -Force | Out-Null
    Write-Host "✅ 软链接创建成功!" -ForegroundColor Green
    Write-Host "   $targetConfigPath -> $sourceConfigPath" -ForegroundColor Gray
}
catch {
    Write-Warning "⚠️  软链接创建失败，尝试硬链接..."
    try {
        New-Item -ItemType HardLink -Path $targetConfigPath -Target $sourceConfigPath -Force | Out-Null
        Write-Host "✅ 硬链接创建成功!" -ForegroundColor Green
    }
    catch {
        Write-Warning "⚠️  硬链接创建失败，使用文件复制..."
        Copy-Item $sourceConfigPath $targetConfigPath -Force
        Write-Host "✅ 文件复制成功!" -ForegroundColor Green
        Write-Host "   注意: 使用文件复制，源文件修改不会自动同步" -ForegroundColor Yellow
    }
}

# =============================================
# 插件管理
# =============================================

if ($InstallPlugins) {
    Write-Host ""
    Write-Host "📦 管理插件依赖..." -ForegroundColor Cyan
    
    # 安装 lazy.nvim
    if (-not (Install-LazyNvim)) {
        Write-Warning "⚠️  lazy.nvim 安装失败，跳过插件安装"
    } else {
        # 安装插件
        Install-Plugins -ConfigPath $targetConfigPath
    }
}

# =============================================
# 配置验证
# =============================================

if ($Verify) {
    Write-Host ""
    if (-not (Test-ConfigSyntax -ConfigPath $targetConfigPath)) {
        Write-Error "❌ 配置验证失败"
        exit 1
    }
}

# =============================================
# 安装验证和完成信息
# =============================================

Write-Host ""
Write-Host "🔍 验证安装..." -ForegroundColor Cyan
if (Test-Path $targetConfigPath) {
    $linkInfo = Get-Item $targetConfigPath
    $linkType = if ($linkInfo.LinkType -eq "SymbolicLink") { "符号链接" }
                elseif ($linkInfo.LinkType -eq "HardLink") { "硬链接" }
                else { "普通文件" }
    
    Write-Host "✅ 安装验证成功" -ForegroundColor Green
    Write-Host "   类型: $linkType" -ForegroundColor Gray
    Write-Host "   大小: $([math]::Round($linkInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
    Write-Host "   修改时间: $($linkInfo.LastWriteTime)" -ForegroundColor Gray
    
    if ($linkInfo.Target) {
        Write-Host "   目标: $($linkInfo.Target)" -ForegroundColor Gray
    }
} else {
    Write-Error "❌ 验证失败: 目标文件不存在"
    exit 1
}

# 完成信息
Write-Host ""
Write-Host "🎉 VSCode Neovim 配置安装完成!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 后续步骤:" -ForegroundColor Cyan
Write-Host "1. 确保已安装 VSCode Neovim 扩展" -ForegroundColor White
Write-Host "2. 在 VSCode 设置中配置 Neovim 路径" -ForegroundColor White
Write-Host "3. 重启 VSCode 或重新加载窗口" -ForegroundColor White
Write-Host "4. 打开任意文件测试 Vim 功能" -ForegroundColor White
Write-Host "5. 按空格键查看可用命令" -ForegroundColor White
Write-Host ""
Write-Host "📚 使用指南:" -ForegroundColor Cyan
Write-Host "- 查看 README.md 了解详细使用说明" -ForegroundColor White
Write-Host "- 按 's' + 字符进行快速跳转" -ForegroundColor White
Write-Host "- 使用 'gcc' 切换行注释" -ForegroundColor White
Write-Host "- 使用 'ys' + 动作 + 符号添加包围符号" -ForegroundColor White
Write-Host ""
Write-Host "💡 提示: 修改配置请编辑源文件: $sourceConfigPath" -ForegroundColor Yellow

if ($InstallPlugins) {
    Write-Host ""
    Write-Host "🔄 首次启动可能需要一些时间来下载插件" -ForegroundColor Yellow
    Write-Host "如遇到问题，请查看 README.md 中的故障排除部分" -ForegroundColor Yellow
}