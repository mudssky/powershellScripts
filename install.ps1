#!/usr/bin/env pwsh

<#
.SYNOPSIS
    准备 PowerShell 脚本开发环境，配置 PATH 并构建子项目

.DESCRIPTION
    该脚本执行以下操作：
    1. 自动检测并添加项目根目录和 bin 目录到 PATH 环境变量 (Windows)。
    2. 同步 bin 目录下的 PowerShell 脚本包装器。
    3. 安装并构建 scripts/node 下的 TypeScript/Node.js 工具集。

.EXAMPLE
    .\install.ps1
#>

[CmdletBinding()]
param()

# --- 防止无限循环 ---
if ($env:PWSH_SCRIPTS_INSTALL_RUNNING -eq 'true') {
    Write-Host "检测到 install.ps1 正在运行，跳过递归调用以防止无限循环。" -ForegroundColor Yellow
    return
}
$env:PWSH_SCRIPTS_INSTALL_RUNNING = 'true'

# --- 配置部分 ---
$ProjectRoot = $PSScriptRoot
$BinDir = Join-Path $ProjectRoot 'bin'
$NodeScriptsDir = Join-Path $ProjectRoot 'scripts/node'

# --- 函数定义 ---

function Test-DirectoryInPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )
    
    # 获取当前 PATH 环境变量（优先 User 级别，然后 Machine 级别）
    # 注意：在非 Windows 平台上，GetEnvironmentVariable 的 Target 参数可能行为不同或被忽略
    if ($IsWindows) {
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    }
    $processPath = $env:PATH
    
    # 合并所有级别的 PATH
    $allPaths = @()
    if ($userPath) { $allPaths += $userPath }
    if ($machinePath) { $allPaths += $machinePath }
    if ($processPath) { $allPaths += $processPath }
    
    # 获取目标目录的绝对路径
    try {
        $targetAbsolutePath = (Resolve-Path -Path $DirectoryPath).Path
        if ($IsWindows) { $targetAbsolutePath = $targetAbsolutePath.ToLowerInvariant() }
    }
    catch {
        Write-Warning "无法解析目标路径: $DirectoryPath"
        return $false
    }
    
    # 检查每个 PATH 条目
    foreach ($pathString in $allPaths) {
        $pathEntries = $pathString -split [IO.Path]::PathSeparator
        
        foreach ($entry in $pathEntries) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            
            $trimmedEntry = $entry.Trim()
            
            # 简单字符串比较
            if ($IsWindows) {
                if ($trimmedEntry.ToLowerInvariant() -eq $targetAbsolutePath) { return $true }
            }
            else {
                if ($trimmedEntry -eq $targetAbsolutePath) { return $true }
            }
            
            # 解析路径后比较
            if (Test-Path $trimmedEntry) {
                try {
                    $resolvedEntry = (Resolve-Path -Path $trimmedEntry).Path
                    if ($IsWindows) { $resolvedEntry = $resolvedEntry.ToLowerInvariant() }
                    
                    if ($resolvedEntry -eq $targetAbsolutePath) {
                        return $true
                    }
                }
                catch { continue }
            }
        }
    }
    
    return $false
}

function Add-DirectoryToPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )
    
    try {
        $currentPath = [Environment]::GetEnvironmentVariable('PATH', $Scope)
        
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $newPath = $DirectoryPath
        }
        else {
            $newPath = $currentPath + [IO.Path]::PathSeparator + $DirectoryPath
        }
        
        [Environment]::SetEnvironmentVariable('PATH', $newPath, $Scope)
        Write-Host "成功将目录添加到 $Scope PATH: $DirectoryPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "添加目录到 PATH 失败: $($_.Exception.Message)"
        return $false
    }
}

function Update-CurrentSessionPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )
    $env:PATH = $env:PATH + [IO.Path]::PathSeparator + $DirectoryPath
    Write-Host "已更新当前会话 PATH: $DirectoryPath" -ForegroundColor Cyan
}

function Ensure-PathSetup {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not $IsWindows) {
        # 非 Windows 环境暂不支持自动修改持久化 PATH
        Write-Warning "非 Windows 环境跳过 PATH 自动配置: $Description"
        return $false
    }

    if (-not (Test-Path $Path)) {
        Write-Warning "目录不存在，跳过 PATH 配置: $Path"
        return $false
    }

    Write-Host "`n检测 $Description 是否在 PATH 中..." -ForegroundColor Yellow
    if (Test-DirectoryInPath -DirectoryPath $Path) {
        Write-Host "✓ $Description 已在 PATH 中" -ForegroundColor Green
        return $false
    }
    else {
        Write-Host "✗ $Description 不在 PATH 中，正在添加..." -ForegroundColor Red
        if (Add-DirectoryToPath -DirectoryPath $Path -Scope 'User') {
            Update-CurrentSessionPath -DirectoryPath $Path
            return $true
        }
    }
    return $false
}

function Install-NodeScripts {
    param(
        [string]$ScriptDir
    )

    if (-not (Test-Path $ScriptDir)) {
        Write-Warning "Node 脚本目录不存在: $ScriptDir"
        return
    }

    Write-Host "`n=== 开始安装 Node.js 脚本工具集 ===" -ForegroundColor Magenta
    
    # 检查 pnpm
    if (-not (Get-Command "pnpm" -ErrorAction SilentlyContinue)) {
        Write-Error "未找到 pnpm，请先安装 pnpm (npm install -g pnpm)"
        return
    }

    # 禁止 Corepack 下载提示
    $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'

    Push-Location $ScriptDir
    try {
        Write-Host "正在安装依赖..." -ForegroundColor Cyan
        pnpm install --ignore-scripts
        if ($LASTEXITCODE -ne 0) { throw "pnpm install 失败" }

        Write-Host "正在构建项目..." -ForegroundColor Cyan
        pnpm run build
        if ($LASTEXITCODE -ne 0) { throw "pnpm run build 失败" }

        Write-Host "✓ Node.js 脚本安装完成" -ForegroundColor Green
    }
    catch {
        Write-Error "Node.js 脚本安装过程中出错: $_"
    }
    finally {
        Pop-Location
    }
}

function Install-NbStripout {
    Write-Host "`n=== 开始安装与配置 nbstripout ===" -ForegroundColor Magenta
    
    # 1. 检查 nbstripout 是否已安装在系统中
    if (-not (Get-Command "nbstripout" -ErrorAction SilentlyContinue)) {
        Write-Host "未找到 nbstripout，尝试通过 pip 安装..." -ForegroundColor Cyan
        if (Get-Command "pip" -ErrorAction SilentlyContinue) {
            pip install nbstripout
            if ($LASTEXITCODE -ne 0) {
                Write-Error "pip install nbstripout 失败"
                return
            }
        }
        else {
            Write-Warning "未找到 pip，请先安装 Python 和 pip，或者手动安装 nbstripout"
            return
        }
    }
    else {
        Write-Host "✓ nbstripout 已安装在系统中" -ForegroundColor Green
    }
}

function Install-AutoHotkey {
    # 使用脚本内的 $ProjectRoot 变量，需通过参数传入或作用域获取
    # 这里我们定义参数以明确依赖
    param($RootPath)

    if (-not $IsWindows) { return }
    
    Write-Host "`n=== 配置 AutoHotkey 环境 ===" -ForegroundColor Magenta
    
    $AhkDir = Join-Path $RootPath 'scripts/ahk'
    
    if (-not (Test-Path $AhkDir)) {
        return
    }
    
    Push-Location $AhkDir
    try {
        if (Test-Path ".\makeScripts.ps1") {
            Write-Host "正在检查 AutoHotkey 配置..." -ForegroundColor Cyan
            # 执行构建脚本
            & .\makeScripts.ps1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ AutoHotkey 配置完成" -ForegroundColor Green
            }
            else {
                Write-Warning "AutoHotkey 配置脚本可能有警告或错误 (Exit Code: $LASTEXITCODE)"
            }
        }
    }
    catch {
        Write-Error "AutoHotkey 配置执行失败: $_"
    }
    finally {
        Pop-Location
    }
}

# --- 主执行逻辑 ---

Write-Host "开始准备 PowerShell 脚本开发环境..." -ForegroundColor Green
Write-Host "项目根目录: $ProjectRoot" -ForegroundColor White

$changesMade = $false

# 1. 配置项目根目录 PATH (仅 Windows)
if (Ensure-PathSetup -Path $ProjectRoot -Description "项目根目录") {
    $changesMade = $true
}

# 2. 同步 bin 目录脚本
Write-Host "`n=== 同步脚本到 bin 目录 ===" -ForegroundColor Magenta
try {
    & (Join-Path $ProjectRoot 'Manage-BinScripts.ps1') -Action 'sync' -Force
}
catch {
    Write-Warning "同步脚本失败: $($_.Exception.Message)"
}

# 3. 安装 Node.js 脚本 (跨平台)
Install-NodeScripts -ScriptDir $NodeScriptsDir

# 4. 配置 bin 目录 PATH (仅 Windows)
#    注意：Node 脚本构建后会生成文件到 bin，所以确保 bin 在 PATH 中很重要
if (Ensure-PathSetup -Path $BinDir -Description "Bin 目录") {
    $changesMade = $true
}

# 5. 安装与配置 nbstripout (Python 工具)
Install-NbStripout

# 6. 配置 AutoHotkey (仅 Windows)
Install-AutoHotkey -RootPath $ProjectRoot

# --- 结束汇总 ---
Write-Host "`n=== 环境准备完成! ===" -ForegroundColor Green
if ($changesMade) {
    Write-Host "⚠️  环境变量已更新，建议重新启动终端以确保所有更改生效" -ForegroundColor Yellow
}
else {
    Write-Host "✓ 环境变量无需更新" -ForegroundColor Green
}

# 设置win环境path
if ($IsWindows) {
    Write-Host "`n当前 PATH 包含 (相关项):" -ForegroundColor Cyan
    $env:PATH -split [IO.Path]::PathSeparator | Where-Object { 
        $_ -match [regex]::Escape($ProjectRoot) -or $_ -match [regex]::Escape($BinDir) 
    } | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor White
    }
}

# 设置 Shell 环境 (Linux/macOS)
if ($IsLinux -or $IsMacOS) {
    Write-Host "`n=== 配置 Shell 环境 ===" -ForegroundColor Magenta
    
    # 检测默认 Shell
    $defaultShell = $env:SHELL
    if ([string]::IsNullOrWhiteSpace($defaultShell)) {
        $defaultShell = "Unknown"
    }
    Write-Host "检测到默认 Shell: $defaultShell" -ForegroundColor Cyan

    $ShellScript = Join-Path $ProjectRoot 'linux/01manage-shell-snippet.sh'
    
    if (Test-Path $ShellScript) {
        try {
            Write-Host "正在执行 Shell 配置脚本: $ShellScript" -ForegroundColor Cyan
            
            # 确保脚本具有执行权限
            if ($IsLinux -or $IsMacOS) {
                & chmod +x $ShellScript
            }
            
            # 执行脚本
            & $ShellScript
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Shell 配置脚本执行成功" -ForegroundColor Green
            }
            else {
                Write-Warning "Shell 配置脚本执行失败，退出码: $LASTEXITCODE"
            }
        }
        catch {
            Write-Error "执行 Shell 配置脚本时出错: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "未找到 Shell 配置脚本: $ShellScript"
    }
}
