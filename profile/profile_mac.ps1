


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
        # zoxide = { 
        #     Write-Verbose "初始化 zoxide 目录跳转工具"
        #     Invoke-Expression (& { (zoxide init powershell | Out-String) }) 
        # }
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