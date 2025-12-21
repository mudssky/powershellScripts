
[CmdletBinding()]
param(
    [switch]$loadProfile,
    [string]$AliasDescPrefix = '[mudssky]'
)
$profileLoadStartTime = Get-Date

# 加载自定义模块 (例如包含 Test-EXEProgram 的文件)
. $PSScriptRoot/loadModule.ps1

# 加载自定义函数包装
. $PSScriptRoot/wrapper.ps1

# 初次使用时，执行loadProfile覆盖本地profile
if ($loadProfile) {
    # 备份逻辑，执行覆盖时备份，防止数据丢失
    if (Test-Path -Path $profile) {
        # 备份文件名添加时间戳，支持多次备份
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$profile.$timestamp.bak"
        Write-Warning "发现现有的profile文件，备份为 $backupPath"
        Copy-Item -Path $profile -Destination $backupPath -Force
    }
    Set-Content -Path $profile  -Value  ". $PSCommandPath"
    return 
}
# 自定义别名配置
$userAlias = . $PSScriptRoot/user_aliases.ps1


 

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
    Get-CustomAlias -AliasDespPrefix $AliasDescPrefix | Format-Table -AutoSize

    # 1.5 函数别名
    Write-Host "`n[自定义函数别名]" -ForegroundColor Yellow
    $userAlias | Where-Object { $_.PSObject.Properties.Name -contains 'command' } | Select-Object @{N = '函数名'; E = 'aliasName' }, @{N = '底层命令'; E = 'command' }, @{N = '描述'; E = 'description' } | Format-Table -AutoSize
	
    # 2. 显示自定义函数包装
    # 动态获取自定义函数包装配置
    $customFunctionWrappers = Get-CustomFunctionWrapperInfos
    Write-Host "`n[自定义函数包装]" -ForegroundColor Yellow
    if ($customFunctionWrappers -and $customFunctionWrappers.Count -gt 0) {
        $customFunctionWrappers | Select-Object @{
            N = '函数名'; E = 'functionName'
        }, @{
            N = '描述'; E = 'description'
        } | Format-Table -AutoSize
    }
    else {
        Write-Host "  暂无自定义函数包装" -ForegroundColor Gray
    }
	
    # 3. 显示此 Profile 文件中定义的核心函数
    Write-Host "`n[核心管理函数]" -ForegroundColor Yellow
    # 假设你的自定义函数都在一个模块里，或者你可以用其他方式过滤
    # 这里我们简单地列出几个关键函数
    "Initialize-Environment", "Show-MyProfileHelp", "Add-CondaEnv" | ForEach-Object { 
        try {
            Get-Command $_ -ErrorAction Stop
        }
        catch {
            # 忽略不存在的函数
        }
    } | Format-Table Name, CommandType, Source -AutoSize

    # 4. 显示关键环境变量  
    Write-Host "`n[关键环境变量]" -ForegroundColor Yellow
    $envVars = @(
        'POWERSHELL_SCRIPTS_ROOT',
        'http_proxy',
        'https_proxy',
        'RUSTC_WRAPPER',
        'YAZI_FILE_ONE'
    )
    foreach ($var in $envVars) {
        $valueItem = Get-Item -Path "Env:$var" -ErrorAction SilentlyContinue
        if ($null -ne $valueItem) {
            Write-Host ("{0,-25} : {1}" -f $var, $valueItem.Value)
        }
    }

    Write-Host "`n[用户级持久环境变量]" -ForegroundColor Yellow
    $persistVars = @('POWERSHELL_SCRIPTS_ROOT', 'http_proxy', 'https_proxy')
    foreach ($var in $persistVars) {
        $uval = [Environment]::GetEnvironmentVariable($var, "User")
        if ($uval) { Write-Host ("{0,-25} : {1}" -f "$var(用户级)", $uval) }
    }

    Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
}


function Set-AliasProfile {
    [CmdletBinding()]
    param (
        [PSCustomObject]$userAlias = $userAlias
    )
    begin {
    }
	
    process {
        # 设置PowerShell别名
        Write-Verbose "设置PowerShell别名"
        Set-CustomAlias -Name ise -Value powershell_ise  -AliasDespPrefix $AliasDescPrefix -Scope Global
        Set-CustomAlias -Name ipython -Value Start-Ipython  -AliasDespPrefix $AliasDescPrefix  -Scope Global
        foreach ($alias in $userAlias) {
            if ($alias.command) {
                Write-Verbose "别名 $($alias.aliasName) 已设置函数，执行函数创建"
                $scriptBlock = [scriptblock]::Create("$($alias.command) `$args")
                New-Item -Path "Function:Global:$($alias.aliasName)" -Value $scriptBlock -Force  | Out-Null
                Write-Verbose "已创建函数: $($alias.aliasName)"
                continue
            }
            # 设置别名时，PowerShell 不需要目标命令当前就存在。它只在你使用该别名时才会去解析命令。因此，可以安全地移除所有 Test-ExeProgram 检查。
            # if (Test-ExeProgram -Name $alias.cliName) {
            Set-CustomAlias -Name $alias.aliasName -Value $alias.aliasValue -Description $alias.description -AliasDespPrefix $AliasDescPrefix -Scope Global
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
		初始化PowerShell环境配置
	.DESCRIPTION
		初始化PowerShell环境配置，包括代理设置、编码配置、别名设置、工具初始化等。
		这个函数封装了所有对环境变量有影响的配置，便于重复调用。
	.PARAMETER ScriptRoot
		脚本根目录路径，默认为当前脚本所在目录
	.PARAMETER EnableProxy
		是否启用代理设置，默认根据enableProxy文件存在性决定
	.PARAMETER ProxyUrl
		代理服务器地址，默认为 http://127.0.0.1:7890
	.EXAMPLE
		Initialize-Environment
		使用默认配置初始化环境
	.EXAMPLE
		Initialize-Environment -EnableProxy $false
		初始化环境但不启用代理
	.EXAMPLE
		Initialize-Environment -ProxyUrl "http://127.0.0.1:8080"
		使用自定义代理地址初始化环境
	.NOTES
		此函数会影响当前PowerShell会话的环境变量和配置
	#>
	
    [CmdletBinding()]
    param (
        [string]$ScriptRoot = $PSScriptRoot,
        [bool]$EnableProxy = (Test-Path -Path "$PSScriptRoot\enableProxy"),
        [ValidatePattern('^https?://')][string]$ProxyUrl = "http://127.0.0.1:7890",
        [switch]$SkipTools,
        [switch]$SkipStarship,
        [switch]$SkipZoxide,
        [switch]$SkipAliases,
        [switch]$Minimal
    )

    Write-Verbose "开始初始化PowerShell环境配置"
    $ErrorActionPreference = 'Stop'
	
    if ($Minimal -or (Test-Path -Path "$PSScriptRoot\minimal") -or $env:POWERSHELL_PROFILE_MINIMAL) {
        $SkipTools = $true
        $SkipAliases = $true
    }
    # 设置代理环境变量
    # 设置项目根目录环境变量
    $Global:Env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $PSScriptRoot
    # 自动检测代理
    Set-Proxy -Command auto
    # 加载自定义环境变量脚本 (用于存放机密或个人配置)
    if (Test-Path -Path (Join-Path -Path $ScriptRoot -ChildPath 'env.ps1')) {
        Write-Verbose "加载自定义环境变量脚本: $(Join-Path -Path $ScriptRoot -ChildPath 'env.ps1')"
        . (Join-Path -Path $ScriptRoot -ChildPath 'env.ps1')
    }
	
    Write-Verbose "设置控制台编码为UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
	
    # 导入PSReadLine模块
    # pwsh 7.x版本以上是自动启用了，所以也不用导入
    # 	Write-Verbose "导入PSReadLine模块"
    # 	try {
    # 		Import-Module PSReadLine -ErrorAction Stop
    # 	}
    #  catch {
    # 		Write-Warning "无法导入PSReadLine模块: $($_.Exception.Message)"
    # 	}
	
    # 初始化开发工具
    Write-Verbose "初始化开发工具"
    $Global:__ZoxideInitialized = $false
    $tools = @{
        starship = { 
            if ($SkipTools -or $SkipStarship) { return }
            Write-Verbose "初始化Starship提示符"
            $starshipFile = Invoke-WithFileCache -Key "starship-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { & starship init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
            . $starshipFile
        }
        sccache  = {
            if ($SkipTools) { return }
            Write-Verbose "设置sccache用于Rust编译缓存"
            $Global:Env:RUSTC_WRAPPER = 'sccache' 
        }
        zoxide   = { 
            if ($SkipTools -or $SkipZoxide) { return }
            Write-Verbose "初始化zoxide目录跳转工具"
            $zoxideFile = Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
            . $zoxideFile
            $Global:__ZoxideInitialized = $true
        }
    }
	
    foreach ($tool in $tools.GetEnumerator()) {
        if ($SkipTools -and ($tool.Key -ne 'starship' -and $tool.Key -ne 'zoxide' -and $tool.Key -ne 'sccache')) {
            continue
        }
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
            if ($tool.Key -eq 'starship') {
                Write-Host -ForegroundColor Yellow '未安装starship（一款开源提示符美化工具），可以运行以下命令进行安装：
1. choco install starship
2. scoop install starship
3. winget install starship'
            }
            else {
                Write-Verbose "工具 $($tool.Key) 未安装，跳过初始化"
            }
        }
    }
	
    if (-not $SkipAliases) { Set-AliasProfile }
    if (-not $Global:__ZoxideInitialized -and -not $SkipZoxide -and (Test-EXEProgram -Name 'zoxide')) {
        function Global:z { & (Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')); Remove-Item function:Global:z -Force; & z @args }
    }
    # 载入conda环境（如果环境变量中没有conda命令）
    # if (-not (Test-EXEProgram -Name conda)) {
    # 	Write-Verbose "尝试加载Conda环境"
    # 	Add-CondaEnv
    # }
	
    # Write-Host "PowerShell环境初始化完成" -ForegroundColor Green
    Write-Debug "PowerShell环境初始化完成" 
}



# 调用环境初始化函数
Initialize-Environment 

# 配置git,解决中文文件名不能正常显示的问题
# git config --global core.quotepath false

$profileLoadEndTime = Get-Date
$profileLoadTime = ($profileLoadEndTime - $profileLoadStartTime).TotalMilliseconds
if ($profileLoadTime -gt 1000) {
    Write-Host "Profile 加载耗时: $($profileLoadTime) 毫秒" -ForegroundColor Green
}

