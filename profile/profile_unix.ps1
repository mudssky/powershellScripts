


<#
.SYNOPSIS
    linux/macOS PowerShell 环境配置脚本

.DESCRIPTION
    初始化 linux/macOS 下的 PowerShell 环境，包括加载模块、初始化开发工具等。
    支持将配置加载到 PowerShell 配置文件中。

.PARAMETER LoadProfile
    是否将当前脚本路径写入到 PowerShell 配置文件中，以便每次启动时自动加载

.EXAMPLE
    ./profile_unix.ps1
    仅初始化当前会话的环境

.EXAMPLE
    ./profile_unix.ps1 -LoadProfile
    初始化环境并将配置写入 PowerShell 配置文件

.NOTES
    作者: mudssky
    版本: 2.0
    最后更新: 2024
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "是否将配置加载到 PowerShell 配置文件中")]
    [switch]$LoadProfile,
    [string]$AliasDespPrefix = '[mudssky]'
)

# 加载自定义模块
. $PSScriptRoot/loadModule.ps1

# 自定义别名配置
$customUserAlias = @(
    [PSCustomObject]@{
        cliName     = 'dust'
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
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'zq'
        aliasValue  = ''
        description = 'zoxide query 用于查询zoxide的数据库，显示最近访问的目录。'
        command     = 'zoxide query'

    }
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'za'
        aliasValue  = ''
        description = 'zoxide add 用于将当前目录添加到zoxide的数据库中，以便下次快速访问。'
        command     = 'zoxide add'
    }
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'zr'
        aliasValue  = 'zoxide'
        description = '如果你不希望某个目录再出现在 zoxide 的候选项中'
        command     = 'zoxide remove'

    }
    # scoop下载下来就是btm，不用设置别名
    # [PSCustomObject]@{
    # 	cliName     = 'bottom'
    # 	aliasName   = 'btm'
    # 	aliasValue  = 'bottom'
    # 	description = 'bottom 是一个用于显示系统资源使用情况的命令行工具。它可以实时显示CPU、内存、磁盘和网络等系统资源的使用情况，帮助用户监控系统性能。'
    # }
)
function Set-AliasProfile {
    [CmdletBinding()]
    param (
        [PSCustomObject]$userAlias = $customUserAlias
    )
    begin {
    }
	
    process {
        # 设置PowerShell别名
        Write-Verbose "设置PowerShell别名"
        Set-CustomAlias -Name ise -Value powershell_ise  -AliasDespPrefix $AliasDespPrefix -Scope Global
        Set-CustomAlias -Name ipython -Value Start-Ipython  -AliasDespPrefix $AliasDespPrefix  -Scope Global
        foreach ($alias in $userAlias) {
            if ($alias.command) {
                Write-Verbose "别名 $($alias.aliasName) 已设置函数，执行函数创建"
                $scriptBlock = [scriptblock]::Create("$($alias.command) `$args")
                New-Item -Path "Function:Global:$($alias.aliasName)" -Value $scriptBlock -Force  | Out-Null
                Write-Verbose "已创建函数: $($alias.name)"
                continue
            }
            # 设置别名时，PowerShell 不需要目标命令当前就存在。它只在你使用该别名时才会去解析命令。因此，可以安全地移除所有 Test-ExeProgram 检查。
            # if (Test-ExeProgram -Name $alias.cliName) {
            Set-CustomAlias -Name $alias.aliasName -Value $alias.aliasValue -Description $alias.description -AliasDespPrefix $AliasDespPrefix -Scope Global
            Write-Verbose "已设置别名: $($alias.aliasName) -> $($alias.aliasValue)"
        }
        # else {
        # 	Write-Warning "未找到 $($alias.cliName) 命令，无法设置别名: $($alias.aliasName)"
        # }
	
    }
	
    end {
		
    }
}
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
        [string]$ScriptRoot = $PSScriptRoot,
        [switch]$SkipTools,
        [switch]$SkipStarship,
        [switch]$SkipZoxide,
        [switch]$SkipAliases,
        [switch]$Minimal
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
    # 添加 Linuxbrew bin 目录到 PATH
    if (Test-Path -Path "/home/linuxbrew/.linuxbrew/bin") {
        $env:PATH += ":/home/linuxbrew/.linuxbrew/bin/"
    }
    if ($IsLinux) {
        try {
            # 缓存半天
            Sync-PathFromBash -CacheSeconds (4 * 3600)  -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "同步 PATH 失败: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    # 自动检测代理
    Set-Proxy -Command auto

    if ($Minimal -or (Test-Path -Path (Join-Path $PSScriptRoot 'minimal')) -or $env:POWERSHELL_PROFILE_MINIMAL) {
        $SkipTools = $true
        $SkipAliases = $true
    }
    Write-Verbose "初始化开发工具"
    $Global:__ZoxideInitialized = $false
    $tools = @{
        starship = { 
            if ($SkipTools -or $SkipStarship) { return }
            Write-Verbose "初始化 Starship 提示符"
            $starshipFile = Invoke-WithFileCache -Key "starship-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { & starship init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
            . $starshipFile
        }
        fnm      = { 
            if ($SkipTools) { return }
            Write-Verbose "初始化 fnm Node.js 版本管理器"
            fnm env --use-on-cd | Out-String | Invoke-Expression 
        }
        zoxide   = { 
            if ($SkipTools -or $SkipZoxide) { return }
            Write-Verbose "初始化 zoxide 目录跳转工具"
            $zoxideFile = Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
            . $zoxideFile
            $Global:__ZoxideInitialized = $true
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
    
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    if (-not $SkipAliases) { Set-AliasProfile }
    if (-not $SkipAliases) { Set-CustomAliasesProfile }
    if (-not $Global:__ZoxideInitialized -and -not $SkipZoxide -and (Test-EXEProgram -Name 'zoxide')) {
        function Global:z { & (Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')); Remove-Item function:Global:z -Force; & z @args }
    }
    Write-Verbose "PowerShell 环境初始化完成"
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
        if (Test-EXEProgram -Name $alias.cliName) {
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
