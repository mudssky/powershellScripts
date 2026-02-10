# PSScriptAnalyzer 抑制：PS 5.1 兼容性赋值，仅在 $IsWindows 未定义时执行
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "是否将配置加载到 PowerShell 配置文件中")]
    [switch]$LoadProfile,
    [string]$AliasDescPrefix = '[mudssky]'
)

# PowerShell 5.1 兼容性：$IsWindows 等变量未定义时回退
if ($null -eq $IsWindows) { $IsWindows = $true; $IsLinux = $false; $IsMacOS = $false }

$profileLoadStartTime = Get-Date

function Test-EnvSwitchEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $item = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    if (-not $item) { return $false }

    $rawValue = [string]$item.Value
    if ([string]::IsNullOrWhiteSpace($rawValue)) { return $false }

    switch ($rawValue.Trim().ToLowerInvariant()) {
        '0' { return $false }
        'false' { return $false }
        'off' { return $false }
        'no' { return $false }
        'n' { return $false }
        default { return $true }
    }
}

function Test-EnvValuePresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $item = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return -not [string]::IsNullOrWhiteSpace([string]$item.Value)
}

function Set-ProfileUtf8Encoding {
    [CmdletBinding()]
    param()

    Write-Verbose "设置控制台编码为 UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

    if (Get-Command -Name Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        if (Get-Command -Name Register-FzfHistorySmartKeyBinding -ErrorAction SilentlyContinue) {
            Register-FzfHistorySmartKeyBinding | Out-Null
        }
    }
}

function Get-ProfileModeDecision {
    [CmdletBinding()]
    param()

    # reason 枚举（V1 固化）
    # explicit_full
    # explicit_mode_full
    # explicit_mode_minimal
    # explicit_mode_ultra
    # explicit_ultra_minimal
    # auto_codex_thread
    # auto_codex_sandbox_network_disabled
    # default_full

    $v2Fields = [ordered]@{
        phase_ms   = $null
        ps_version = [string]$PSVersionTable.PSVersion
        host       = [string]$Host.Name
        pid        = $PID
    }

    $diagOnlyMarkers = @()
    if (Test-EnvValuePresent -Name 'CODEX_MANAGED_BY_NPM') { $diagOnlyMarkers += 'CODEX_MANAGED_BY_NPM(diag_only)' }
    if (Test-EnvValuePresent -Name 'CODEX_MANAGED_BY_BUN') { $diagOnlyMarkers += 'CODEX_MANAGED_BY_BUN(diag_only)' }

    # 优先级：FULL > MODE > ULTRA_MINIMAL > auto > default
    if (Test-EnvSwitchEnabled -Name 'POWERSHELL_PROFILE_FULL') {
        return [PSCustomObject]@{
            Mode      = 'Full'
            Source    = 'explicit'
            Reason    = 'explicit_full'
            Markers   = @('POWERSHELL_PROFILE_FULL') + $diagOnlyMarkers
            ElapsedMs = 0
            V2        = [PSCustomObject]$v2Fields
        }
    }

    $profileMode = [string]$env:POWERSHELL_PROFILE_MODE
    if (-not [string]::IsNullOrWhiteSpace($profileMode)) {
        switch ($profileMode.Trim().ToLowerInvariant()) {
            'full' {
                return [PSCustomObject]@{
                    Mode      = 'Full'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_full'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'normal' {
                return [PSCustomObject]@{
                    Mode      = 'Full'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_full'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'minimal' {
                return [PSCustomObject]@{
                    Mode      = 'Minimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_minimal'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'fast' {
                return [PSCustomObject]@{
                    Mode      = 'Minimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_minimal'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'light' {
                return [PSCustomObject]@{
                    Mode      = 'Minimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_minimal'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'ultra' {
                return [PSCustomObject]@{
                    Mode      = 'UltraMinimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_ultra'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'ultraminimal' {
                return [PSCustomObject]@{
                    Mode      = 'UltraMinimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_ultra'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
            'ultra-minimal' {
                return [PSCustomObject]@{
                    Mode      = 'UltraMinimal'
                    Source    = 'explicit_mode'
                    Reason    = 'explicit_mode_ultra'
                    Markers   = @("POWERSHELL_PROFILE_MODE=$profileMode") + $diagOnlyMarkers
                    ElapsedMs = 0
                    V2        = [PSCustomObject]$v2Fields
                }
            }
        }
    }

    # 兼容旧版 Minimal 环境开关（手动触发）
    $manualMinimalMarkers = @(
        'POWERSHELL_PROFILE_MINIMAL',
        'POWERSHELL_PROFILE_FAST',
        'POWERSHELL_PROFILE_LIGHT'
    )
    $hitManualMinimalMarkers = @()
    foreach ($marker in $manualMinimalMarkers) {
        if (Test-EnvSwitchEnabled -Name $marker) {
            $hitManualMinimalMarkers += $marker
        }
    }
    if ($hitManualMinimalMarkers.Count -gt 0) {
        return [PSCustomObject]@{
            Mode      = 'Minimal'
            Source    = 'explicit_mode'
            Reason    = 'explicit_mode_minimal'
            Markers   = $hitManualMinimalMarkers + $diagOnlyMarkers
            ElapsedMs = 0
            V2        = [PSCustomObject]$v2Fields
        }
    }

    if (Test-EnvSwitchEnabled -Name 'POWERSHELL_PROFILE_ULTRA_MINIMAL') {
        return [PSCustomObject]@{
            Mode      = 'UltraMinimal'
            Source    = 'explicit'
            Reason    = 'explicit_ultra_minimal'
            Markers   = @('POWERSHELL_PROFILE_ULTRA_MINIMAL') + $diagOnlyMarkers
            ElapsedMs = 0
            V2        = [PSCustomObject]$v2Fields
        }
    }

    # 自动降级仅检测 V1 变量：CODEX_THREAD_ID / CODEX_SANDBOX_NETWORK_DISABLED
    $autoMarkers = @()
    if (Test-EnvValuePresent -Name 'CODEX_THREAD_ID') { $autoMarkers += 'CODEX_THREAD_ID' }
    if (Test-EnvValuePresent -Name 'CODEX_SANDBOX_NETWORK_DISABLED') { $autoMarkers += 'CODEX_SANDBOX_NETWORK_DISABLED' }

    if ($autoMarkers.Count -gt 0) {
        $autoReason = 'auto_codex_sandbox_network_disabled'
        if ($autoMarkers -contains 'CODEX_THREAD_ID') {
            $autoReason = 'auto_codex_thread'
        }

        return [PSCustomObject]@{
            Mode      = 'UltraMinimal'
            Source    = 'auto'
            Reason    = $autoReason
            Markers   = $autoMarkers + $diagOnlyMarkers
            ElapsedMs = 0
            V2        = [PSCustomObject]$v2Fields
        }
    }

    return [PSCustomObject]@{
        Mode      = 'Full'
        Source    = 'default'
        Reason    = 'default_full'
        Markers   = $diagOnlyMarkers
        ElapsedMs = 0
        V2        = [PSCustomObject]$v2Fields
    }
}

function Write-ProfileModeDecisionSummary {
    [CmdletBinding()]
    param()

    $script:ProfileModeDecision.ElapsedMs = [int]((Get-Date) - $profileLoadStartTime).TotalMilliseconds
    $markerText = '-'
    if ($script:ProfileModeDecision.Markers -and $script:ProfileModeDecision.Markers.Count -gt 0) {
        $markerText = ($script:ProfileModeDecision.Markers -join ',')
    }

    Write-Verbose ("[ProfileMode] mode={0} source={1} reason={2} markers={3} elapsed_ms={4}" -f $script:ProfileModeDecision.Mode, $script:ProfileModeDecision.Source, $script:ProfileModeDecision.Reason, $markerText, $script:ProfileModeDecision.ElapsedMs)
}

function Write-ProfileModeFallbackGuide {
    [CmdletBinding()]
    param(
        [switch]$VerboseOnly
    )

    $guideLines = @(
        '手动兜底：POWERSHELL_PROFILE_FULL=1 强制 Full',
        '手动兜底：POWERSHELL_PROFILE_MODE=full|minimal|ultra 显式指定模式',
        '手动兜底：POWERSHELL_PROFILE_ULTRA_MINIMAL=1 强制 UltraMinimal'
    )

    foreach ($line in $guideLines) {
        if ($VerboseOnly) {
            Write-Verbose $line
        }
        else {
            Write-Host "  - $line" -ForegroundColor Gray
        }
    }
}

$script:ProfileModeDecision = Get-ProfileModeDecision
$script:ProfileMode = [string]$script:ProfileModeDecision.Mode
$script:UseMinimalProfile = $script:ProfileMode -eq 'Minimal'
$script:UseUltraMinimalProfile = $script:ProfileMode -eq 'UltraMinimal'
$script:ProfileExtendedFeaturesLoaded = $false
$userAlias = @()

if (-not $script:UseUltraMinimalProfile) {
    # 加载自定义模块 (包含 Test-EXEProgram、Set-CustomAlias 等)
    $loadModuleScript = Join-Path $PSScriptRoot 'loadModule.ps1'
    try {
        . $loadModuleScript
    }
    catch {
        Write-Error "[profile/profile.ps1] dot-source 失败: $loadModuleScript :: $($_.Exception.Message)"
        throw
    }

    # 加载自定义函数包装 (yaz, Add-CondaEnv 等)
    $wrapperScript = Join-Path $PSScriptRoot 'wrapper.ps1'
    try {
        . $wrapperScript
    }
    catch {
        Write-Error "[profile/profile.ps1] dot-source 失败: $wrapperScript :: $($_.Exception.Message)"
        throw
    }

    # 自定义别名配置
    $userAliasScript = Join-Path $PSScriptRoot 'user_aliases.ps1'
    try {
        $userAlias = . $userAliasScript
    }
    catch {
        Write-Error "[profile/profile.ps1] dot-source 失败: $userAliasScript :: $($_.Exception.Message)"
        throw
    }

    $script:ProfileExtendedFeaturesLoaded = $true
}
else {
    Write-Verbose 'UltraMinimal 模式已生效：跳过模块、包装函数与用户别名脚本加载'
}

<#
.SYNOPSIS
    显示当前 Profile 加载的自定义别名、函数和关键环境变量。
#>
function Show-MyProfileHelp {
    [CmdletBinding()]
    param()

    Write-Host "--- PowerShell Profile 帮助 ---" -ForegroundColor Cyan
    Write-Host ("当前模式: {0}" -f $script:ProfileMode) -ForegroundColor DarkCyan

    if (-not $script:ProfileExtendedFeaturesLoaded) {
        Write-Host "`n[功能降级提示]" -ForegroundColor Yellow
        Write-Host "  当前处于 UltraMinimal 模式，已跳过模块/别名/工具等高级功能加载。" -ForegroundColor Gray
        Write-Host "  如需完整能力，请使用以下任一方式后重新加载：" -ForegroundColor Gray
        Write-ProfileModeFallbackGuide
        Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
        return
    }

    # 1. 自定义别名
    Write-Host "`n[自定义别名]" -ForegroundColor Yellow
    Get-CustomAlias -AliasDespPrefix $AliasDescPrefix | Format-Table -AutoSize

    # 2. 自定义函数别名
    Write-Host "`n[自定义函数别名]" -ForegroundColor Yellow
    $userAlias |
        Where-Object { $_.PSObject.Properties.Name -contains 'command' } |
        Select-Object @{
            N = '函数名'; E = 'aliasName'
        }, @{
            N = '底层命令'; E = {
                if ($_.PSObject.Properties.Name -contains 'commandArgs' -and $null -ne $_.commandArgs -and @($_.commandArgs).Count -gt 0) {
                    "$($_.command) $((@($_.commandArgs)) -join ' ')"
                }
                else {
                    $_.command
                }
            }
        }, @{
            N = '描述'; E = 'description'
        } | Format-Table -AutoSize

    # 3. 自定义函数包装
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

    # 4. 核心管理函数
    Write-Host "`n[核心管理函数]" -ForegroundColor Yellow
    "Initialize-Environment", "Show-MyProfileHelp", "Add-CondaEnv" | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Where-Object { $_ } | Format-Table Name, CommandType, Source -AutoSize

    # 5. 关键环境变量
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

    # 6. 用户级持久环境变量（仅 Windows 支持）
    if ($IsWindows) {
        Write-Host "`n[用户级持久环境变量]" -ForegroundColor Yellow
        $persistVars = @('POWERSHELL_SCRIPTS_ROOT', 'http_proxy', 'https_proxy')
        foreach ($var in $persistVars) {
            $uval = [Environment]::GetEnvironmentVariable($var, "User")
            if ($uval) { Write-Host ("{0,-25} : {1}" -f "$var(用户级)", $uval) }
        }
    }

    Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
}

function Set-AliasProfile {
    [CmdletBinding()]
    param (
        [PSCustomObject]$userAlias = $userAlias
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
        - UltraMinimal：仅保留 UTF8、基础兼容变量与 POWERSHELL_SCRIPTS_ROOT，跳过其余步骤。
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
        当前不实现 CI 自动判定与自动降级逻辑（YAGNI）
    #>
    [CmdletBinding()]
    param (
        [string]$ScriptRoot = $PSScriptRoot,
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

    if ($script:UseUltraMinimalProfile) {
        Write-Verbose "UltraMinimal 模式：仅执行最小初始化路径"

        # 极简模式仅保留三项：根目录变量、UTF8 编码、基础兼容变量（顶部已处理）
        $Global:Env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $PSScriptRoot
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

    if ($Minimal -or (Test-Path -Path (Join-Path $PSScriptRoot 'minimal')) -or (Test-EnvSwitchEnabled -Name 'POWERSHELL_PROFILE_MINIMAL')) {
        $SkipTools = $true
        $SkipAliases = $true
        Write-Verbose "命中 Minimal 开关，跳过工具初始化与别名注册"
    }

    # 设置项目根目录环境变量
    $Global:Env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $PSScriptRoot

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
    $envScriptPath = Join-Path -Path $ScriptRoot -ChildPath 'env.ps1'
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
            $starshipFile = Invoke-WithFileCache -Key "starship-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { & starship init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
            . $starshipFile
        }
        zoxide   = {
            if ($SkipTools -or $SkipZoxide) { return }
            Write-Verbose "初始化 zoxide 目录跳转工具"
            $zoxideFile = Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')
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
        function Global:z { & (Invoke-WithFileCache -Key "zoxide-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $PSScriptRoot '.cache')); Remove-Item function:Global:z -Force; & z @args }
    }

    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
    Write-Debug "PowerShell 环境初始化完成"
}

<#
.SYNOPSIS
    设置 PowerShell 配置文件
.DESCRIPTION
    将当前脚本路径写入到 PowerShell 配置文件中，确保每次启动时自动加载。
    如果已有配置文件，会先备份（带时间戳后缀）。
#>
function Set-PowerShellProfile {
    [CmdletBinding()]
    param()

    try {
        # 备份逻辑：覆盖前备份，防止数据丢失
        if (Test-Path -Path $profile) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$profile.$timestamp.bak"
            Write-Warning "发现现有的profile文件，备份为 $backupPath"
            Copy-Item -Path $profile -Destination $backupPath -Force
        }

        # 确保 profile 目录存在
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

# === 主执行逻辑 ===
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
}

# 加载耗时统计
$profileLoadEndTime = Get-Date
$profileLoadTime = ($profileLoadEndTime - $profileLoadStartTime).TotalMilliseconds
if ($profileLoadTime -gt 1000) {
    if (-not $script:UseMinimalProfile) {
        Write-Host "Profile 加载耗时: $($profileLoadTime) 毫秒" -ForegroundColor Green
    }
}
