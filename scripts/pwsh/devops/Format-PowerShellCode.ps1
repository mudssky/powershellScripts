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

.PARAMETER GitChanged
    仅格式化 Git 工作区中有改动的 PowerShell 文件（含已暂存与未暂存）。

.PARAMETER Strict
    启用严格模式，使用 Invoke-Formatter 默认完整规则集（包含大小写修正）。

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

.EXAMPLE
    .\Format-PowerShellCode.ps1 -GitChanged
    仅格式化 Git 改动文件

.EXAMPLE
    .\Format-PowerShellCode.ps1 -GitChanged -Strict
    严格模式下仅格式化 Git 改动文件

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
    [switch]$ShowOnly,

    [Parameter(HelpMessage = "仅格式化 Git 改动文件")]
    [switch]$GitChanged,

    [Parameter(HelpMessage = "严格模式：使用 Invoke-Formatter 默认完整规则")]
    [switch]$Strict
)

# 默认激进规则：保留核心排版规则，排除高耗时大小写修正规则
function Get-AggressiveFormatterSettings {
    [CmdletBinding()]
    param()

    return @{
        IncludeRules = @(
            'PSPlaceOpenBrace',
            'PSPlaceCloseBrace',
            'PSUseConsistentWhitespace',
            'PSUseConsistentIndentation',
            'PSUseConsistentLineEndings',
            'PSAlignAssignmentStatement'
        )
    }
}

function Get-FormatterSettingsSource {
    [CmdletBinding()]
    param(
        [string]$SettingsPath,
        [switch]$UseStrictMode
    )

    if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
        if (-not (Test-Path -Path $SettingsPath -PathType Leaf)) {
            throw "指定的 Settings 文件不存在: $SettingsPath"
        }

        return @{
            Kind = 'Path'
            Value = $SettingsPath
        }
    }

    if ($UseStrictMode) {
        return @{
            Kind = 'Default'
            Value = $null
        }
    }

    return @{
        Kind = 'Hashtable'
        Value = Get-AggressiveFormatterSettings
    }
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

# 确保所需模块可用（直接导入，失败后再安装）
function Ensure-PSScriptAnalyzerModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "$ModuleName 模块未安装或无法导入，正在安装..." -ForegroundColor Yellow
    }

    if (-not (Install-RequiredModule -ModuleName $ModuleName)) {
        return $false
    }

    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "导入 $ModuleName 模块失败: $($_.Exception.Message)"
        return $false
    }
}

# 格式化单个文件
function Format-SingleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$FormatterSettingsSource
    )
    
    try {
        Write-Verbose "正在格式化文件: $FilePath"
        
        # 读取文件内容
        $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        
        # 准备 Invoke-Formatter 参数
        $formatterParams = @{
            ScriptDefinition = $content
        }
        
        # 根据模式注入 formatter settings
        if ($FormatterSettingsSource.Kind -eq 'Path') {
            $formatterParams.Settings = $FormatterSettingsSource.Value
        }
        elseif ($FormatterSettingsSource.Kind -eq 'Hashtable') {
            $formatterParams.Settings = $FormatterSettingsSource.Value
        }
        
        # 执行格式化
        $formattedContent = Invoke-Formatter @formatterParams

        if ($content -ceq $formattedContent) {
            Write-Verbose "文件内容未变化，跳过写回: $FilePath"
            return $true
        }
        
        # 将格式化后的内容写回文件
        [System.IO.File]::WriteAllText($FilePath, $formattedContent, [System.Text.Encoding]::UTF8)
        
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
    
    $extensions = @('.ps1', '.psm1', '.psd1')
    $files = [System.Collections.Generic.List[string]]::new()
    
    if (Test-Path -Path $Path -PathType Leaf) {
        # 单个文件
        $fileInfo = Get-Item -Path $Path
        if ($fileInfo.Extension -in @('.ps1', '.psm1', '.psd1')) {
            $null = $files.Add($fileInfo.FullName)
        }
        else {
            Write-Warning "文件 $Path 不是支持的 PowerShell 文件类型"
        }
    }
    elseif (Test-Path -Path $Path -PathType Container) {
        # 目录：单次遍历后按扩展名筛选
        if ($Recurse) {
            $items = Get-ChildItem -Path $Path -Recurse -File
        }
        else {
            $items = Get-ChildItem -Path $Path -File
        }

        foreach ($item in $items) {
            if ($item.Extension -in $extensions) {
                $null = $files.Add($item.FullName)
            }
        }
    }
    else {
        Write-Error "路径不存在: $Path"
        return @()
    }
    
    return @($files)
}

# 获取 Git 改动的 PowerShell 文件
function Get-GitChangedPowerShellFiles {
    [CmdletBinding()]
    param()

    try {
        $gitRoot = (git rev-parse --show-toplevel 2>$null)
    }
    catch {
        Write-Error "无法检测到 Git 仓库根目录，请确认当前目录在 Git 仓库内"
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
        Write-Error "无法检测到 Git 仓库根目录，请确认当前目录在 Git 仓库内"
        return @()
    }

    $powerShellPathspec = @('*.ps1', '*.psm1', '*.psd1')

    $changed = @()
    $changed += git -C $gitRoot diff --name-only --diff-filter=ACMRT -- @powerShellPathspec
    $changed += git -C $gitRoot diff --name-only --diff-filter=ACMRT --cached -- @powerShellPathspec

    $changed = $changed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
    if ($changed.Count -eq 0) {
        return @()
    }

    $fullPaths = foreach ($rel in $changed) {
        $candidate = Join-Path $gitRoot $rel
        if (Test-Path -Path $candidate -PathType Leaf) {
            $candidate
        }
    }

    @($fullPaths)
}

# 主函数
function Main {
    $allFilesToFormat = @()

    if ($GitChanged) {
        $allFilesToFormat += Get-GitChangedPowerShellFiles
    }
    else {
        # 验证是否有路径参数
        if (-not $Path -or $Path.Count -eq 0) {
            Write-Error "请提供要格式化的文件或目录路径"
            Write-Host "使用方法: .\\Format-PowerShellCode.ps1 file1.ps1 file2.psm1" -ForegroundColor Yellow
            exit 1
        }
    
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
    }

    # 去重
    $allFilesToFormat = $allFilesToFormat | Sort-Object -Unique

    if ($allFilesToFormat.Count -eq 0) {
        if ($GitChanged) {
            Write-Host "未找到 Git 改动的 PowerShell 文件，已快速退出" -ForegroundColor DarkYellow
        }
        else {
            Write-Warning "在指定路径中未找到 PowerShell 文件"
        }
        return
    }

    # 解析 formatter settings 源：优先外部设置文件，其次 strict，再次默认 aggressive
    try {
        $formatterSettingsSource = Get-FormatterSettingsSource -SettingsPath $Settings -UseStrictMode:$Strict
    }
    catch {
        Write-Error $_
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Settings)) {
        Write-Host "使用外部 formatter settings: $Settings" -ForegroundColor DarkCyan
    }
    elseif ($Strict) {
        Write-Host "严格模式：使用 Invoke-Formatter 完整默认规则" -ForegroundColor DarkCyan
    }
    else {
        Write-Host "默认模式：使用激进性能规则（不含 PSUseCorrectCasing）" -ForegroundColor DarkCyan
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

    if (-not (Ensure-PSScriptAnalyzerModule -ModuleName 'PSScriptAnalyzer')) {
        Write-Error "无法使用 PSScriptAnalyzer 模块，脚本退出"
        return
    }
    
    # 执行格式化
    $successCount = 0
    $failCount = 0
    
    foreach ($file in $allFilesToFormat) {
        if ($PSCmdlet.ShouldProcess($file, "格式化 PowerShell 文件")) {
            if (Format-SingleFile -FilePath $file -FormatterSettingsSource $formatterSettingsSource) {
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
