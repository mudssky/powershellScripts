<#
.SYNOPSIS
    使用 Invoke-Formatter 命令格式化 PowerShell 代码文件

.DESCRIPTION
    使用 PSScriptAnalyzer 的 Invoke-Formatter 命令格式化 PowerShell 代码文件。
    支持格式化单个文件、多个文件或整个目录（可选递归）。
    支持的文件类型包括：.ps1, .psm1, .psd1
    特别适用于 lint-staged 等工具的多文件批量处理。

.PARAMETER Path
    要格式化的文件或目录路径。支持多个路径，可以通过位置参数传递。

.PARAMETER Recurse
    递归处理子目录中的 PowerShell 文件。

.PARAMETER Settings
    PSScriptAnalyzer 设置文件的路径。如果未指定，将使用默认设置。

.PARAMETER ShowOnly
    显示将要格式化的文件列表，但不实际执行格式化操作。

.EXAMPLE
    .\Format-PowerShellCode.ps1 script.ps1
    格式化单个文件

.EXAMPLE
    .\Format-PowerShellCode.ps1 script1.ps1 script2.psm1 module.psd1
    格式化多个文件

.EXAMPLE
    .\Format-PowerShellCode.ps1 "C:\Scripts" -Recurse
    递归格式化目录中的所有 PowerShell 文件

.EXAMPLE
    .\Format-PowerShellCode.ps1 script1.ps1 script2.psm1 -ShowOnly
    显示将要格式化的多个文件，但不实际执行

.EXAMPLE
    # lint-staged 配置示例
    pwsh -File ./scripts/Format-PowerShellCode.ps1

.OUTPUTS
    System.String
    输出格式化操作的结果信息

.NOTES
    作者: mudssky
    需要安装 PSScriptAnalyzer 模块才能使用 Invoke-Formatter 命令
    运行前请确保已安装：Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true, HelpMessage = "要格式化的文件或目录路径（支持多个文件）")]
    [string[]]$Path,
    
    [Parameter(HelpMessage = "递归处理子目录")]
    [switch]$Recurse,
    
    [Parameter(HelpMessage = "PSScriptAnalyzer 设置文件路径")]
    [string]$Settings,
    
    [Parameter(HelpMessage = "显示将要格式化的文件，但不实际执行")]
    [switch]$ShowOnly
)

# 验证是否有路径参数
if (-not $Path -or $Path.Count -eq 0) {
    Write-Error "请提供要格式化的文件或目录路径"
    Write-Host "使用方法: .\\Format-PowerShellCode.ps1 file1.ps1 file2.psm1" -ForegroundColor Yellow
    exit 1
}

# 检查 PSScriptAnalyzer 模块是否已安装
function Test-ModuleInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    $module = Get-Module -ListAvailable -Name $ModuleName
    return ($null -ne $module)
}

# 安装必需的模块
function Install-RequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    Write-Host "正在安装模块: $ModuleName" -ForegroundColor Yellow
    try {
        Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber
        Write-Host "模块 $ModuleName 安装成功" -ForegroundColor Green
    }
    catch {
        Write-Error "安装模块 $ModuleName 失败: $($_.Exception.Message)"
        return $false
    }
    return $true
}

# 格式化单个文件
function Format-SingleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string]$SettingsPath
    )
    
    try {
        Write-Verbose "正在格式化文件: $FilePath"
        
        # 读取文件内容
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        
        # 准备 Invoke-Formatter 参数
        $formatterParams = @{
            ScriptDefinition = $content
        }
        
        # 如果指定了设置文件，添加到参数中
        if (-not [string]::IsNullOrWhiteSpace($SettingsPath) -and (Test-Path $SettingsPath)) {
            $formatterParams.Settings = $SettingsPath
        }
        
        # 执行格式化
        $formattedContent = Invoke-Formatter @formatterParams
        
        # 将格式化后的内容写回文件
        Set-Content -Path $FilePath -Value $formattedContent -Encoding UTF8 -NoNewline
        
        Write-Host "✓ 已格式化: $FilePath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "格式化文件失败 $FilePath : $($_.Exception.Message)"
        return $false
    }
}

# 获取要处理的 PowerShell 文件列表
function Get-PowerShellFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [bool]$Recurse
    )
    
    $extensions = @('*.ps1', '*.psm1', '*.psd1')
    $files = @()
    
    if (Test-Path -Path $Path -PathType Leaf) {
        # 单个文件
        $fileInfo = Get-Item -Path $Path
        if ($fileInfo.Extension -in @('.ps1', '.psm1', '.psd1')) {
            $files += $fileInfo.FullName
        }
        else {
            Write-Warning "文件 $Path 不是支持的 PowerShell 文件类型"
        }
    }
    elseif (Test-Path -Path $Path -PathType Container) {
        # 目录
        foreach ($extension in $extensions) {
            if ($Recurse) {
                $files += Get-ChildItem -Path $Path -Filter $extension -Recurse -File | Select-Object -ExpandProperty FullName
            }
            else {
                $files += Get-ChildItem -Path $Path -Filter $extension -File | Select-Object -ExpandProperty FullName
            }
        }
    }
    else {
        Write-Error "路径不存在: $Path"
        return @()
    }
    
    return $files
}

# 主函数
function Main {
    # 检查并安装 PSScriptAnalyzer 模块
    if (-not (Test-ModuleInstalled -ModuleName 'PSScriptAnalyzer')) {
        Write-Host "PSScriptAnalyzer 模块未安装，正在安装..." -ForegroundColor Yellow
        if (-not (Install-RequiredModule -ModuleName 'PSScriptAnalyzer')) {
            Write-Error "无法安装 PSScriptAnalyzer 模块，脚本退出"
            return
        }
    }
    
    # 导入模块
    try {
        Import-Module PSScriptAnalyzer -Force
    }
    catch {
        Write-Error "导入 PSScriptAnalyzer 模块失败: $($_.Exception.Message)"
        return
    }
    
    $allFilesToFormat = @()
    
    # 处理每个传入的路径
    foreach ($singlePath in $Path) {
        # 验证路径
        if (-not (Test-Path -Path $singlePath)) {
            Write-Warning "指定的路径不存在: $singlePath"
            continue
        }
        
        # 直接处理单个文件或使用 Get-PowerShellFiles 处理目录
        if (Test-Path -Path $singlePath -PathType Leaf) {
            # 单个文件 - 直接检查扩展名
            $fileInfo = Get-Item -Path $singlePath
            if ($fileInfo.Extension -in @('.ps1', '.psm1', '.psd1')) {
                $allFilesToFormat += $fileInfo.FullName
            }
            else {
                Write-Warning "文件 $singlePath 不是支持的 PowerShell 文件类型"
            }
        }
        else {
            # 目录 - 使用现有函数
            $filesToFormat = Get-PowerShellFiles -Path $singlePath -Recurse $Recurse.IsPresent
            $allFilesToFormat += $filesToFormat
        }
    }
    
    # 去重
    $allFilesToFormat = $allFilesToFormat | Sort-Object -Unique
    
    if ($allFilesToFormat.Count -eq 0) {
        Write-Warning "在指定路径中未找到 PowerShell 文件"
        return
    }
    
    Write-Host "找到 $($allFilesToFormat.Count) 个 PowerShell 文件" -ForegroundColor Cyan
    
    # ShowOnly 模式：只显示文件列表
    if ($ShowOnly) {
        Write-Host "将要格式化的文件:" -ForegroundColor Yellow
        foreach ($file in $allFilesToFormat) {
            Write-Host "  - $file" -ForegroundColor Gray
        }
        return
    }
    
    # 执行格式化
    $successCount = 0
    $failCount = 0
    
    foreach ($file in $allFilesToFormat) {
        if ($PSCmdlet.ShouldProcess($file, "格式化 PowerShell 文件")) {
            if (Format-SingleFile -FilePath $file -SettingsPath $Settings) {
                $successCount++
            }
            else {
                $failCount++
            }
        }
    }
    
    # 输出结果统计
    Write-Host "`n格式化完成!" -ForegroundColor Green
    Write-Host "成功: $successCount 个文件" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "失败: $failCount 个文件" -ForegroundColor Red
    }
}

# 执行主函数
Main