function Set-AliasProfile {
    [CmdletBinding()]
    param (
        [PSCustomObject]$userAlias = $script:userAlias
    )

    process {
        # 设置 PowerShell 别名
        Write-Verbose "设置PowerShell别名"
        Set-CustomAlias -Name ise -Value powershell_ise -AliasDespPrefix $AliasDescPrefix -Scope Global
        Set-CustomAlias -Name ipython -Value Start-Ipython -AliasDespPrefix $AliasDescPrefix -Scope Global
        foreach ($alias in $userAlias) {
            if ($alias.PSObject.Properties.Name -contains 'command' -and -not [string]::IsNullOrWhiteSpace([string]$alias.command)) {
                $command = [string]$alias.command
                $commandArgs = @()
                if ($alias.PSObject.Properties.Name -contains 'commandArgs' -and $null -ne $alias.commandArgs) {
                    $commandArgs = @($alias.commandArgs)
                }
                Write-Verbose "别名 $($alias.aliasName) 已设置函数，执行函数创建"
                $scriptBlock = {
                    param(
                        [Parameter(ValueFromRemainingArguments = $true)]
                        [object[]]$RemainingArgs
                    )
                    & $command @commandArgs @RemainingArgs
                }.GetNewClosure()
                New-Item -Path "Function:Global:$($alias.aliasName)" -Value $scriptBlock -Force | Out-Null
                Write-Verbose "已创建函数: $($alias.aliasName)"
                continue
            }
            Set-CustomAlias -Name $alias.aliasName -Value $alias.aliasValue -Description $alias.description -AliasDespPrefix $AliasDescPrefix -Scope Global
            Write-Verbose "已设置别名: $($alias.aliasName) -> $($alias.aliasValue)"
        }
    }
}

function Initialize-Environment {
    <#
    .SYNOPSIS
        初始化 PowerShell 环境配置（跨平台统一入口）
    .DESCRIPTION
        初始化 PowerShell 环境配置，包括代理设置、编码配置、别名设置、工具初始化等。
        通过 $IsWindows/$IsLinux/$IsMacOS 自动适配平台差异。
        模式差异：
        - Full：默认全能力初始化。
        - Minimal：仅跳过工具初始化与别名注册（保留模块能力，不自动触发）。
        - UltraMinimal：仅保留 UTF8 与 POWERSHELL_SCRIPTS_ROOT，跳过其余步骤。
    .PARAMETER ScriptRoot
        脚本根目录路径，默认为当前脚本所在目录
    .PARAMETER ProxyUrl
        代理服务器地址，默认为 http://127.0.0.1:7890
    .PARAMETER SkipTools
        跳过所有工具初始化
    .PARAMETER SkipProxy
        跳过代理自动检测
    .PARAMETER SkipStarship
        跳过 Starship 初始化
    .PARAMETER SkipZoxide
        跳过 Zoxide 初始化
    .PARAMETER SkipAliases
        跳过别名设置
    .PARAMETER Minimal
        最小化模式，等同于同时指定 -SkipTools -SkipAliases
    .EXAMPLE
        Initialize-Environment
        使用默认配置初始化环境
    .EXAMPLE
        Initialize-Environment -Minimal
        最小化模式初始化（跳过工具和别名）
    .EXAMPLE
        Initialize-Environment -ProxyUrl "http://127.0.0.1:8080"
        使用自定义代理地址初始化环境
    .NOTES
        此函数会影响当前 PowerShell 会话的环境变量和配置
        运行时基线为 PowerShell 7+（pwsh）
        当前不实现 CI 自动判定与自动降级逻辑（YAGNI）
    #>
    [CmdletBinding()]
    param (
        [string]$ScriptRoot = $script:ProfileRoot,
        [ValidatePattern('^https?://')][string]$ProxyUrl = "http://127.0.0.1:7890",
        [switch]$SkipTools,
        [switch]$SkipProxy,
        [switch]$SkipStarship,
        [switch]$SkipZoxide,
        [switch]$SkipAliases,
        [switch]$Minimal
    )

    Write-Verbose "开始初始化 PowerShell 环境配置"
    Write-Verbose ("Profile 模式提示: {0}" -f $script:ProfileMode)

    if (-not [string]::IsNullOrWhiteSpace($ScriptRoot)) {
        $script:ProfileRoot = $ScriptRoot
    }
    $profileRoot = if (-not [string]::IsNullOrWhiteSpace($script:ProfileRoot)) {
        $script:ProfileRoot
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $PSScriptRoot
    }
    else {
        (Get-Location).Path
    }

    if ($script:UseUltraMinimalProfile) {
        Write-Verbose "UltraMinimal 模式：仅执行最小初始化路径"

        # 极简模式仅保留两项：根目录变量、UTF8 编码
        $rootForEnv = if (-not [string]::IsNullOrWhiteSpace($ScriptRoot)) { $ScriptRoot } else { $profileRoot }
        $env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $rootForEnv
        Set-ProfileUtf8Encoding

        Write-ProfileModeDecisionSummary
        Write-ProfileModeFallbackGuide -VerboseOnly
        Write-Debug "PowerShell 环境初始化完成（UltraMinimal）"
        return
    }

    if ($script:UseMinimalProfile) {
        $SkipTools = $true
        $SkipAliases = $true
        Write-Verbose "检测到 Minimal 模式，自动跳过工具初始化与别名注册"
    }

    if ($Minimal -or (Test-Path -Path (Join-Path $profileRoot 'minimal')) -or (Test-EnvSwitchEnabled -Name 'POWERSHELL_PROFILE_MINIMAL')) {
        $SkipTools = $true
        $SkipAliases = $true
        Write-Verbose "命中 Minimal 开关，跳过工具初始化与别名注册"
    }

    # 设置项目根目录环境变量
    $env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $profileRoot

    # === 平台特定：Linux PATH 同步 ===
    if ($IsLinux) {
        # 添加 Linuxbrew bin 目录到 PATH
        if (Test-Path -Path "/home/linuxbrew/.linuxbrew/bin") {
            $env:PATH += ":/home/linuxbrew/.linuxbrew/bin/"
        }
        try {
            # 从 Bash 同步 PATH（缓存 4 小时）
            Sync-PathFromBash -CacheSeconds (4 * 3600) -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "同步 PATH 失败: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    # 自动检测代理
    if (-not $SkipProxy) {
        Set-Proxy -Command auto
    }
    else {
        Write-Verbose "跳过代理自动检测"
    }

    # 加载自定义环境变量脚本 (用于存放机密或个人配置)
    $envScriptPath = Join-Path -Path $profileRoot -ChildPath 'env.ps1'
    if (Test-Path -Path $envScriptPath) {
        Write-Verbose "加载自定义环境变量脚本: $envScriptPath"
        try {
            . $envScriptPath
        }
        catch {
            Write-Warning "加载环境变量脚本时出错: $($_.Exception.Message)"
        }
    }

    # 设置控制台编码为 UTF8
    Set-ProfileUtf8Encoding

    # === 工具初始化 ===
    Write-Verbose "初始化开发工具"
    $Global:__ZoxideInitialized = $false
    $tools = @{
        starship = {
            if ($SkipTools -or $SkipStarship) { return }
            Write-Verbose "初始化 Starship 提示符"
            $starshipFile = Invoke-WithFileCache -Key "starship-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { & starship init powershell } -BaseDir (Join-Path $profileRoot '.cache')
            . $starshipFile
        }
        zoxide   = {
            if ($SkipTools -or $SkipZoxide) { return }
            Write-Verbose "初始化 zoxide 目录跳转工具"
            $zoxideFile = Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $profileRoot '.cache')
            . $zoxideFile
            $Global:__ZoxideInitialized = $true
        }
        sccache  = {
            # 仅 Windows：Rust 编译缓存
            if (-not $IsWindows -or $SkipTools) { return }
            Write-Verbose "设置 sccache 用于 Rust 编译缓存"
            $Global:Env:RUSTC_WRAPPER = 'sccache'
        }
        fnm      = {
            # 仅 Unix：Node.js 版本管理器
            if ($IsWindows -or $SkipTools) { return }
            Write-Verbose "初始化 fnm Node.js 版本管理器"
            fnm env --use-on-cd | Out-String | Invoke-Expression
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
            # 工具未安装提示（仅对关键工具）
            switch ($tool.Key) {
                'starship' {
                    if ($IsWindows) {
                        Write-Host -ForegroundColor Yellow '未安装starship（一款开源提示符美化工具），可以运行以下命令进行安装：
1. choco install starship
2. scoop install starship
3. winget install starship'
                    }
                    else {
                        Write-Host -ForegroundColor Yellow "未安装 starship（跨平台提示符美化工具），可运行以下命令安装：`nbrew install starship"
                    }
                }
                'fnm' {
                    if (-not $IsWindows) {
                        Write-Host -ForegroundColor Yellow "未安装 fnm（Node.js 版本管理器），可运行以下命令安装：`nbrew install fnm"
                    }
                }
                'zoxide' {
                    if ($IsWindows) {
                        Write-Verbose "工具 zoxide 未安装，跳过初始化"
                    }
                    else {
                        Write-Host -ForegroundColor Yellow "未安装 zoxide（智能目录跳转工具），可运行以下命令安装：`nbrew install zoxide"
                    }
                }
                default {
                    Write-Verbose "工具 $($tool.Key) 未安装，跳过初始化"
                }
            }
        }
    }

    if (-not $SkipAliases) { Set-AliasProfile }

    # z 函数懒加载：zoxide 已安装但未在初始化阶段加载时，首次调用自动初始化
    if (-not $Global:__ZoxideInitialized -and -not $SkipZoxide -and (Test-EXEProgram -Name 'zoxide')) {
        function Global:z { & (Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $script:ProfileRoot '.cache')); Remove-Item function:Global:z -Force; & z @args }
    }

    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
    Write-Debug "PowerShell 环境初始化完成"
}
