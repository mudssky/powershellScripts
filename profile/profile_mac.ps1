


<#
.SYNOPSIS
    macOS PowerShell 环境配置脚本

.DESCRIPTION
    初始化 macOS 下的 PowerShell 环境，包括加载模块、初始化开发工具等。
    支持将配置加载到 PowerShell 配置文件中。

.PARAMETER LoadProfile
    是否将当前脚本路径写入到 PowerShell 配置文件中，以便每次启动时自动加载

.EXAMPLE
    ./profile_mac.ps1
    仅初始化当前会话的环境

.EXAMPLE
    ./profile_mac.ps1 -LoadProfile
    初始化环境并将配置写入 PowerShell 配置文件

.NOTES
    作者: mudssky
    版本: 2.0
    最后更新: 2024
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "是否将配置加载到 PowerShell 配置文件中")]
    [switch]$LoadProfile
)

# 加载自定义模块
. $PSScriptRoot/loadModule.ps1

function Initialize-Environment {
    <#
    .SYNOPSIS
        初始化 PowerShell 环境配置
    
    .DESCRIPTION
        加载环境变量脚本并初始化各种开发工具
    
    .PARAMETER ScriptRoot
        脚本根目录路径
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$ScriptRoot = $PSScriptRoot
    )
    
    Write-Verbose "开始初始化 PowerShell 环境配置"
    
    # 加载自定义环境变量脚本
    $envScriptPath = Join-Path $ScriptRoot "env.ps1"
    if (Test-Path -Path $envScriptPath) {
        Write-Verbose "加载自定义环境变量脚本: $envScriptPath"
        try {
            . $envScriptPath
        }
        catch {
            Write-Warning "加载环境变量脚本时出错: $($_.Exception.Message)"
        }
    }
    
    # 初始化开发工具
    Write-Verbose "初始化开发工具"
    $tools = @{
        starship = { 
            Write-Verbose "初始化 Starship 提示符"
            Invoke-Expression (&starship init powershell) 
        }
        fnm      = { 
            Write-Verbose "初始化 fnm Node.js 版本管理器"
            fnm env --use-on-cd | Out-String | Invoke-Expression 
        }
        zoxide   = { 
            Write-Verbose "初始化 zoxide 目录跳转工具"
            Invoke-Expression (& { (zoxide init powershell | Out-String) }) 
        }
    }
    
    foreach ($tool in $tools.GetEnumerator()) {
        if (Test-EXEProgram -Name $tool.Key) {
            try {
                & $tool.Value
                Write-Verbose "成功初始化工具: $($tool.Key)"
            }
            catch {
                Write-Warning "初始化工具 $($tool.Key) 时出错: $($_.Exception.Message)"
            }
        }
        else {
            switch ($tool.Key) {
                'starship' {
                    Write-Host -ForegroundColor Yellow "未安装 starship（跨平台提示符美化工具），可运行以下命令安装：`nbrew install starship"
                }
                'fnm' {
                    Write-Host -ForegroundColor Yellow "未安装 fnm（Node.js 版本管理器），可运行以下命令安装：`nbrew install fnm"
                }
                'zoxide' {
                    Write-Host -ForegroundColor Yellow "未安装 zoxide（智能目录跳转工具），可运行以下命令安装：`nbrew install zoxide"
                }
                default {
                    Write-Verbose "工具 $($tool.Key) 未安装，跳过初始化"
                }
            }
        }
    }
    
    Write-Verbose "PowerShell 环境初始化完成"
    
    # 设置自定义别名
    Set-CustomAliasesProfile
}

<#
.SYNOPSIS
    显示当前 Profile 加载的自定义别名、函数和关键环境变量。
#>
function Show-MyProfileHelp {
    [CmdletBinding()]
    param(

    )
    Write-Host "--- PowerShell Profile 帮助 ---" -ForegroundColor Cyan

    # 1. 显示自定义别名
    Write-Host "`n[自定义别名]" -ForegroundColor Yellow
    Get-CustomAlias -AliasDespPrefix $AliasDespPrefix | Format-Table -AutoSize

    # 2. 显示此 Profile 文件中定义的函数
    Write-Host "`n[自定义函数]" -ForegroundColor Yellow
    # 假设你的自定义函数都在一个模块里，或者你可以用其他方式过滤
    # 这里我们简单地列出几个关键函数
    "Initialize-Environment", "Show-MyProfileHelp", "Set-CustomAliasesProfile" | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Format-Table Name, CommandType, Source -AutoSize


    # 3. 显示关键环境变量  
    Write-Host "`n[关键环境变量]" -ForegroundColor Yellow
    $envVars = @(
        'POWERSHELL_SCRIPTS_ROOT',
        'http_proxy',
        'https_proxy',
        'RUSTC_WRAPPER'
    )
    foreach ($var in $envVars) {
        if ($value = Get-Variable "env:$var" -ErrorAction SilentlyContinue) {
            Write-Host ("{0,-25} : {1}" -f $var, $value.Value)
        }
    }

    Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
}

function Set-CustomAliasesProfile {
    <#
    .SYNOPSIS
        设置自定义别名
    
    .DESCRIPTION
        为常用命令设置别名，提高命令行使用效率
    #>
    [CmdletBinding()]
    param()
    
    # 使用脚本级别的别名描述前缀
    
    # 定义用户别名配置
    $userAlias = @(
        [PSCustomObject]@{
            cliName     = 'du'
            aliasName   = 'du'
            aliasValue  = 'dust'
            description = 'dust 是一个用于清理磁盘空间的命令行工具。它可以扫描指定目录并显示占用空间较大的文件和目录，以便用户确定是否删除它们。'
        }
        [PSCustomObject]@{
            cliName     = 'duf'
            aliasName   = 'df'
            aliasValue  = 'duf'
            description = 'df 是 du 的别名，用于显示目录内容。'
        }
        # macOS 下可能使用 homebrew 安装的 bottom
        # [PSCustomObject]@{
        #     cliName     = 'bottom'
        #     aliasName   = 'btm'
        #     aliasValue  = 'bottom'
        #     description = 'bottom 是一个用于显示系统资源使用情况的命令行工具。它可以实时显示CPU、内存、磁盘和网络等系统资源的使用情况，帮助用户监控系统性能。'
        # }
    )
    
    foreach ($alias in $userAlias) {
        if (Test-ExeProgram -Name $alias.cliName) {
            Set-CustomAlias -Name $alias.aliasName -Value $alias.aliasValue -Description $alias.description  -Scope Global
            Write-Verbose "已设置别名: $($alias.aliasName) -> $($alias.aliasValue)"
        }
        else {
            switch ($alias.cliName) {
                'dust' {
                    Write-Host -ForegroundColor Yellow "未安装 dust（磁盘使用分析工具），可运行以下命令安装：`nbrew install dust"
                }
                'duf' {
                    Write-Host -ForegroundColor Yellow "未安装 duf（磁盘使用显示工具），可运行以下命令安装：`nbrew install duf"
                }
                default {
                    Write-Warning "未找到 $($alias.cliName) 命令，无法设置别名: $($alias.aliasName)"
                }
            }
        }
    }
}

function Set-PowerShellProfile {
    <#
    .SYNOPSIS
        设置 PowerShell 配置文件
    
    .DESCRIPTION
        将当前脚本路径写入到 PowerShell 配置文件中，确保每次启动时自动加载
    #>
    [CmdletBinding()]
    param()
    
    try {
        # 确保配置文件目录存在
        $profileDir = Split-Path -Path $profile -Parent
        if (-not (Test-Path -Path $profileDir)) {
            Write-Verbose "创建 PowerShell 配置文件目录: $profileDir"
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
        }
        
        # 写入配置文件
        $profileContent = ". `"$PSCommandPath`""
        Set-Content -Path $profile -Value $profileContent -Encoding UTF8
        Write-Host -ForegroundColor Green "已成功将配置写入 PowerShell 配置文件: $profile"
    }
    catch {
        Write-Error "设置 PowerShell 配置文件时出错: $($_.Exception.Message)"
    }
}

# 主执行逻辑
try {
    # 调用环境初始化函数
    Initialize-Environment
    
    # 如果指定了 LoadProfile 参数，则设置配置文件
    if ($LoadProfile) {
        Set-PowerShellProfile
    }
}
catch {
    Write-Error "脚本执行过程中出现错误: $($_.Exception.Message)"
    exit 1
}