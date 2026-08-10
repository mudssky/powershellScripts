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

function Get-ProfileInstallHintPlatform {
    <#
    .SYNOPSIS
        返回安装提示使用的平台标识。

    .PARAMETER PlatformContext
        可选的平台能力上下文；省略时使用 Profile 当前上下文或运行时平台。

    .OUTPUTS
        System.String
        返回 windows、macos 或 linux。
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$PlatformContext = $script:ProfilePlatformContext
    )

    process {
        if ($null -ne $PlatformContext -and -not [string]::IsNullOrWhiteSpace([string]$PlatformContext.Id)) {
            return [string]$PlatformContext.Id
        }
        if ($IsWindows) { return 'windows' }
        if ($IsMacOS) { return 'macos' }
        return 'linux'
    }
}

function Get-ProfileInstallHintDefinitions {
    [CmdletBinding()]
    param()

    process {
        # APT 包名当前按工具名映射；若目标发行版存在差异，在此表中调整即可。
        return [ordered]@{
            starship = [PSCustomObject]@{
                DisplayName = 'starship'
                Description = '跨平台提示符美化工具'
                Platforms   = @('windows', 'macos', 'linux')
                Packages    = [ordered]@{
                    scoop  = 'starship'
                    winget = 'starship'
                    choco  = 'starship'
                    brew   = 'starship'
                    apt    = 'starship'
                }
            }
            zoxide = [PSCustomObject]@{
                DisplayName = 'zoxide'
                Description = '智能目录跳转工具'
                Platforms   = @('windows', 'macos', 'linux')
                Packages    = [ordered]@{
                    scoop = 'zoxide'
                    brew  = 'zoxide'
                    apt   = 'zoxide'
                }
            }
            fnm      = [PSCustomObject]@{
                DisplayName = 'fnm'
                Description = 'Node.js 版本管理器'
                Platforms   = @('macos', 'linux')
                Packages    = [ordered]@{
                    scoop = 'fnm'
                    brew  = 'fnm'
                    apt   = 'fnm'
                }
            }
        }
    }
}

function Test-ProfileInstallHintEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform = (Get-ProfileInstallHintPlatform),
        [switch]$SkipTools,
        [switch]$SkipStarship,
        [switch]$SkipZoxide
    )

    process {
        if ($SkipTools) { return $false }

        $definitions = Get-ProfileInstallHintDefinitions
        if (-not $definitions.Contains($ToolName)) { return $false }

        $definition = $definitions[$ToolName]
        if ($definition.Platforms -notcontains $Platform) { return $false }

        switch ($ToolName) {
            'starship' { return -not $SkipStarship }
            'zoxide' { return -not $SkipZoxide }
            default { return $true }
        }
    }
}

function Get-ProfilePreferredPackageManager {
    [CmdletBinding()]
    param(
        [string[]]$AvailableCommands,
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform = (Get-ProfileInstallHintPlatform)
    )

    process {
        $available = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($commandName in @($AvailableCommands)) {
            if (-not [string]::IsNullOrWhiteSpace($commandName)) {
                $available.Add($commandName) | Out-Null
            }
        }

        $priority = switch ($Platform) {
            'windows' { @('scoop', 'winget', 'choco') }
            'macos' { @('brew') }
            'linux' { @('brew', 'apt') }
        }

        foreach ($packageManager in $priority) {
            if ($available.Contains($packageManager)) {
                return $packageManager
            }
        }

        return $null
    }
}

function Get-ProfilePackageManagerInstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('scoop', 'winget', 'choco', 'brew', 'apt')]
        [string]$PackageManager,
        [string[]]$Packages
    )

    process {
        $resolvedPackages = @($Packages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($resolvedPackages.Count -eq 0) { return $null }

        switch ($PackageManager) {
            'scoop' { return "scoop install $($resolvedPackages -join ' ')" }
            'winget' { return ($resolvedPackages | ForEach-Object { "winget install $_" }) -join '; ' }
            'choco' { return "choco install $($resolvedPackages -join ' ')" }
            'brew' { return "brew install $($resolvedPackages -join ' ')" }
            'apt' { return "sudo apt install $($resolvedPackages -join ' ')" }
            default { return $null }
        }
    }
}

function Get-ProfileMissingToolInstallHint {
    [CmdletBinding()]
    param(
        [string[]]$ToolNames,
        [string[]]$AvailableCommands,
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform = (Get-ProfileInstallHintPlatform)
    )

    process {
        $definitions = Get-ProfileInstallHintDefinitions
        $missingTools = [System.Collections.Generic.List[object]]::new()

        foreach ($toolName in @($ToolNames)) {
            if ([string]::IsNullOrWhiteSpace($toolName)) { continue }
            if (-not $definitions.Contains($toolName)) { continue }

            $definition = $definitions[$toolName]
            if ($definition.Platforms -notcontains $Platform) { continue }

            $missingTools.Add([PSCustomObject]@{
                    ToolName     = $toolName
                    DisplayName  = $definition.DisplayName
                    Description  = $definition.Description
                    PackageNames = $definition.Packages
                }) | Out-Null
        }

        if ($missingTools.Count -eq 0) { return $null }

        $packageManager = Get-ProfilePreferredPackageManager -AvailableCommands $AvailableCommands -Platform $Platform
        $installCommand = $null

        if ($packageManager) {
            $packageNames = foreach ($tool in $missingTools) {
                if ($tool.PackageNames.Contains($packageManager)) {
                    $tool.PackageNames[$packageManager]
                }
            }

            if (@($packageNames).Count -eq $missingTools.Count) {
                $installCommand = Get-ProfilePackageManagerInstallCommand -PackageManager $packageManager -Packages $packageNames
            }
        }

        $toolSummary = ($missingTools | Select-Object -ExpandProperty DisplayName) -join '、'
        $message = if ($installCommand) {
            "未安装以下工具：$toolSummary。可手动执行下面这行命令一次性安装。"
        }
        else {
            "未安装以下工具：$toolSummary。当前未找到可自动拼接的安装命令，请按当前系统包管理器手动安装。"
        }

        return [PSCustomObject]@{
            ToolNames      = @($missingTools | Select-Object -ExpandProperty ToolName)
            PackageManager = $packageManager
            Message        = $message
            Command        = $installCommand
        }
    }
}

function Test-IsProfileLocalEnvPathFilesystemRoot {
    <#
    .SYNOPSIS
        判断路径探测点是否为裸文件系统/盘符根。

    .DESCRIPTION
        仅根路径存在（/、\、C:\、\\server\share）不能证明外接盘或目标目录可用。
        Windows 上 Unix 风格绝对路径的祖先会落到 \，必须排除，否则会误导入坏路径。

    .PARAMETER Path
        待判断的路径字符串。

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $true
        }

        $trimmed = $Path.TrimEnd([char[]]@('\', '/'))
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return $true
        }

        # Windows 盘符根：C: / C:\ / C:/
        if ($Path -match '^[A-Za-z]:[\\/]*$') {
            return $true
        }

        # UNC 共享根：\\server\share
        if ($Path -match '^\\\\[^\\\/]+[\\/][^\\\/]+[\\/]*$') {
            return $true
        }

        return $false
    }
}

function Test-ProfileLocalEnvPathReachable {
    <#
    .SYNOPSIS
        判断路径敏感环境变量的目标路径链是否可达。

    .DESCRIPTION
        目标路径或其任一非根祖先存在时视为可达（允许稍后 mkdir 子路径）。
        裸根存在不计入可达，避免未挂载外接盘或 Windows 盘符根误放行。

    .PARAMETER Path
        环境变量中的路径值。

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $false
        }

        $probe = $Path
        while (-not [string]::IsNullOrWhiteSpace($probe)) {
            if (Test-Path -LiteralPath $probe) {
                # 根存在不等于目标可用
                return -not (Test-IsProfileLocalEnvPathFilesystemRoot -Path $probe)
            }

            $parentProbe = Split-Path -Parent $probe
            if ([string]::IsNullOrWhiteSpace($parentProbe) -or $parentProbe -eq $probe) {
                break
            }
            $probe = $parentProbe
        }

        return $false
    }
}

function Import-ProfileLocalShellEnvFile {
    <#
    .SYNOPSIS
        从 shell env.local.sh 导入 export 行到当前进程环境变量。

    .DESCRIPTION
        只解析 `export NAME=VALUE` 行，忽略注释、空行与 alias。
        用于让 pwsh 与 bash/zsh 共享同一份本机私有环境清单。
        路径类变量（如 CARGO_HOME、SCCACHE_DIR）仅在目标路径已存在，
        或其父级数据盘根目录可访问时才写入，避免外接盘未挂载时写死坏路径。

    .PARAMETER Path
        env.local.sh 文件路径。

    .PARAMETER PathSensitiveNames
        需要做存在性检查的变量名列表。

    .OUTPUTS
        System.Int32
        成功写入的环境变量个数。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$PathSensitiveNames = @(
            'CARGO_HOME',
            'SCCACHE_DIR',
            'RUSTUP_HOME',
            'HERMES_HOME'
        )
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return 0
        }

        $pathSensitive = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$PathSensitiveNames,
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $applied = 0

        foreach ($rawLine in Get-Content -LiteralPath $Path -ErrorAction Stop) {
            $line = $rawLine.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
                continue
            }

            # 仅接受 export NAME=VALUE；不执行任意 shell 语句
            if ($line -notmatch '^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                continue
            }

            $name = $Matches[1]
            $value = $Matches[2].Trim()

            if (
                ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) -or
                ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2)
            ) {
                $value = $value.Substring(1, $value.Length - 2)
            }

            if ($pathSensitive.Contains($name)) {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    continue
                }

                # 目标、任一非根祖先存在即可（外接盘子路径可稍后 mkdir）
                if (-not (Test-ProfileLocalEnvPathReachable -Path $value)) {
                    Write-Verbose "跳过路径变量 $name=$value（路径链均不可达，可能外接盘未挂载）"
                    continue
                }

            }

            Set-Item -Path "Env:$name" -Value $value
            $applied++
        }

        return $applied
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
    .PARAMETER ProfileMode
        当前 Profile 模式。
    .PARAMETER PlatformContext
        当前平台能力上下文。
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
    .OUTPUTS
        System.Void
        此函数不返回对象，仅修改当前 PowerShell 会话环境。
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
        [switch]$Minimal,
        [ValidateSet('Full', 'Minimal', 'UltraMinimal')]
        [string]$ProfileMode = $script:ProfileMode,
        [PSCustomObject]$PlatformContext = $script:ProfilePlatformContext
    )

    Write-Verbose "开始初始化 PowerShell 环境配置"
    Write-Verbose ("Profile 模式提示: {0}" -f $ProfileMode)

    if ($null -eq $PlatformContext) {
        $PlatformContext = Get-ProfilePlatformContext
    }

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

    if ($ProfileMode -eq 'UltraMinimal' -or $script:UseUltraMinimalProfile) {
        Write-Verbose "UltraMinimal 模式：仅执行最小初始化路径"

        Initialize-ProfileBootstrap -ProfileRoot $profileRoot -PlatformContext $PlatformContext

        Write-ProfileModeDecisionSummary
        Write-ProfileModeFallbackGuide -VerboseOnly
        Write-Debug "PowerShell 环境初始化完成（UltraMinimal）"
        return
    }

    $useMinimalInitialization = $false
    if ($ProfileMode -eq 'Minimal' -or $script:UseMinimalProfile) {
        $SkipTools = $true
        $SkipAliases = $true
        $useMinimalInitialization = $true
        Write-Verbose "检测到 Minimal 模式，自动跳过工具初始化与别名注册"
    }

    if ($Minimal -or (Test-Path -Path (Join-Path $profileRoot 'minimal')) -or (Test-EnvSwitchEnabled -Name 'POWERSHELL_PROFILE_MINIMAL')) {
        $SkipTools = $true
        $SkipAliases = $true
        $useMinimalInitialization = $true
        Write-Verbose "命中 Minimal 开关，跳过工具初始化与别名注册"
    }

    # 设置项目根目录环境变量
    $env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $profileRoot
    Add-ProfileRepositoryBinPath -RepositoryRoot $env:POWERSHELL_SCRIPTS_ROOT -PlatformContext $PlatformContext | Out-Null

    # === 平台特定：Linux PATH 同步 ===
    if ($PlatformContext.SyncBashPath) {
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

    # 自动检测代理默认保持开启；PROXY_AUTO_ENABLE=0/false/off/no/n 时跳过检测与缓存回放。
    if ((-not $SkipProxy) -and (Test-EnvSwitchEnabled -Name 'PROXY_AUTO_ENABLE' -DefaultEnabled)) {
        try {
            $proxyState = Invoke-WithCache -Key "proxy-auto-detect" -MaxAge ([TimeSpan]::FromMinutes(30)) -CacheType Text -ScriptBlock {
                Set-Proxy -Command auto
                $result = if ($env:http_proxy) { 'on' } else { 'off' }
                return $result
            }
            if ($proxyState -eq 'on' -and -not $env:http_proxy) {
                Set-Proxy -Command on
            }
        }
        catch {
            Write-Verbose "代理自动检测失败: $($_.Exception.Message)"
            # 回退到不缓存的直接探测
            Set-Proxy -Command auto
        }
    }

    # 加载 shell 本机私有 export（与 bash/zsh 的 env.local.sh 共享）
    $localShellEnvCandidates = @(
        (Join-Path -Path $env:POWERSHELL_SCRIPTS_ROOT -ChildPath 'shell/shared.d/env.local.sh')
        (Join-Path -Path $HOME -ChildPath '.bashrc.d/env.local.sh')
    ) | Select-Object -Unique

    foreach ($localShellEnvPath in $localShellEnvCandidates) {
        if (-not (Test-Path -LiteralPath $localShellEnvPath -PathType Leaf)) {
            continue
        }

        try {
            $importedCount = Import-ProfileLocalShellEnvFile -Path $localShellEnvPath
            Write-Verbose "已从 $localShellEnvPath 导入 $importedCount 个本机环境变量"
            break
        }
        catch {
            Write-Warning "加载 shell 本机环境变量失败 ($localShellEnvPath): $($_.Exception.Message)"
        }
    }

    # 加载自定义环境变量脚本 (用于存放机密或个人配置；可覆盖上面的 shell local)
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

    if ($useMinimalInitialization) {
        Write-ProfileModeDecisionSummary
        Write-ProfileModeFallbackGuide -VerboseOnly
        Write-Debug "PowerShell 环境初始化完成（Minimal）"
        return
    }

    # === 工具初始化 ===
    Write-Verbose "初始化开发工具"
    if (-not (Get-Variable -Name __ZoxideInitialized -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:__ZoxideInitialized = $false
    }
    if (-not (Get-Variable -Name __CarapaceInitialized -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:__CarapaceInitialized = $false
    }
    if (-not (Get-Variable -Name __AtuinInitialized -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:__AtuinInitialized = $false
    }

    # 平台标识符（用于工具缓存 key，防止跨平台缓存交叉污染）
    $runtimePlatform = Get-ProfileInstallHintPlatform -PlatformContext $PlatformContext
    $platformId = [string]$PlatformContext.CacheId

    # 批量检测所有工具与包管理器（避免 Get-Command 未命中回退导致的冷启动卡顿）
    $toolNames = @('starship', 'zoxide', 'sccache', 'fnm', 'carapace', 'atuin')
    $trackedToolNames = if ($PlatformContext.IsWindows) {
        @('starship', 'zoxide', 'sccache', 'carapace', 'atuin')
    }
    else {
        $toolNames
    }
    $packageManagerNames = @($PlatformContext.PackageManagers)
    $trackedCommandNames = @($trackedToolNames + $packageManagerNames)
    $availableCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $availableTools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $missingHintToolNames = [System.Collections.Generic.List[string]]::new()
    try {
        $commandDiscoveryResults = Find-ExecutableCommand -Name $trackedCommandNames -CacheMisses
        if ($commandDiscoveryResults) {
            foreach ($commandResult in $commandDiscoveryResults) {
                if (-not $commandResult.Found) {
                    continue
                }

                $commandName = [string]$commandResult.Name
                if ([string]::IsNullOrWhiteSpace($commandName)) {
                    continue
                }

                $availableCommands.Add($commandName) | Out-Null
                if ($trackedToolNames -contains $commandName) {
                    $availableTools.Add($commandName) | Out-Null
                }
            }
        }
    }
    catch {
        Write-Verbose "命令探测失败，回退为空结果: $($_.Exception.Message)"
    }

    $tools = [ordered]@{
        starship = {
            if ($SkipTools -or $SkipStarship) { return }
            Write-Verbose "初始化 Starship 提示符"
            $cacheDir = Join-Path $profileRoot '.cache'
            $starshipCacheKey = "starship-init-powershell-$platformId-v2"
            $starshipFile = Invoke-WithFileCache `
                -Key $starshipCacheKey `
                -MaxAge ([TimeSpan]::FromDays(7)) `
                -Generator {
                    # starship init 可能返回 string[]；必须显式按换行拼接，避免后续正则时被 PowerShell 隐式拼接成单行
                    $initScriptLines = & starship init powershell --print-full-init 2>$null
                    if ($LASTEXITCODE -ne 0 -or -not $initScriptLines) {
                        Write-Verbose "starship 不支持 --print-full-init，回退到默认 init 输出"
                        $initScriptLines = & starship init powershell
                    }
                    $initScript = ($initScriptLines -join [System.Environment]::NewLine)

                    # Post-processing: 缓存 continuation prompt 输出，避免每次启动 spawn 子进程（~100-150ms）
                    # starship init 输出中包含:
                    #   Set-PSReadLineOption -ContinuationPrompt (
                    #       Invoke-Native -Executable '...' -Arguments @("prompt", "--continuation")
                    #   )
                    # 替换为预先获取的字面量值
                    try {
                        $continuationPrompt = (& starship prompt --continuation) -join [System.Environment]::NewLine
                        if ($continuationPrompt) {
                            # 转义单引号用于嵌入字符串字面量
                            $escaped = $continuationPrompt -replace "'", "''"
                            $pattern = 'Set-PSReadLineOption -ContinuationPrompt \(\s*Invoke-Native -Executable .+? -Arguments @\(\s*"prompt",\s*"--continuation"\s*\)\s*\)'
                            $replacement = "Set-PSReadLineOption -ContinuationPrompt '$escaped'"
                            $result = [regex]::Replace($initScript, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                            if ($result -ne $initScript) {
                                Write-Verbose "starship continuation prompt 已内联缓存"
                                $initScript = $result
                            }
                            else {
                                Write-Verbose "starship continuation prompt 正则替换未匹配，保留原始 Invoke-Native 调用"
                            }
                        }
                    }
                    catch {
                        Write-Verbose "starship continuation prompt 缓存失败，保留原始行为: $($_.Exception.Message)"
                    }

                    $initScript
                } `
                -BaseDir $cacheDir
            . $starshipFile
        }
        zoxide   = {
            if ($SkipTools -or $SkipZoxide) { return }
            Write-Verbose "初始化 zoxide 目录跳转工具"
            $zoxideFile = Invoke-WithFileCache -Key "zoxide-init-powershell-$platformId" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir (Join-Path $profileRoot '.cache')
            . $zoxideFile
            $Global:__ZoxideInitialized = $true
        }
        carapace = {
            if ($SkipTools -or $Global:__CarapaceInitialized) { return }
            Write-Verbose "初始化 Carapace 参数补全"
            $carapaceFile = Invoke-WithFileCache `
                -Key "carapace-init-powershell-$platformId" `
                -MaxAge ([TimeSpan]::FromDays(7)) `
                -Generator {
                    $initScriptLines = & carapace _carapace 2>$null
                    if ($LASTEXITCODE -ne 0 -or -not $initScriptLines) {
                        throw 'carapace _carapace 未返回可用初始化脚本'
                    }
                    $initScriptLines -join [System.Environment]::NewLine
                } `
                -BaseDir (Join-Path $profileRoot '.cache')
            . $carapaceFile
            $Global:__CarapaceInitialized = $true
        }
        atuin    = {
            if ($SkipTools -or $Global:__AtuinInitialized) { return }
            Write-Verbose "初始化 Atuin 历史记录"
            $atuinFile = Invoke-WithFileCache `
                -Key "atuin-init-powershell-$platformId" `
                -MaxAge ([TimeSpan]::FromDays(7)) `
                -Generator {
                    $initScriptLines = & atuin init powershell --disable-up-arrow 2>$null
                    if ($LASTEXITCODE -ne 0 -or -not $initScriptLines) {
                        throw 'atuin init powershell 未返回可用初始化脚本'
                    }
                    $initScriptLines -join [System.Environment]::NewLine
                } `
                -BaseDir (Join-Path $profileRoot '.cache')
            . $atuinFile
            $Global:__AtuinInitialized = $true
        }
        sccache  = {
            # Rust 编译缓存（跨平台）；若 env.local 已设置则保留
            if ($SkipTools) { return }
            Write-Verbose "设置 sccache 用于 Rust 编译缓存"
            if ([string]::IsNullOrWhiteSpace($env:RUSTC_WRAPPER)) {
                $env:RUSTC_WRAPPER = 'sccache'
            }
        }
        fnm      = {
            # 仅 Unix：Node.js 版本管理器
            if ($PlatformContext.IsWindows -or $SkipTools) { return }
            Write-Verbose "初始化 fnm Node.js 版本管理器"
            # fnm env 输出包含会话特定的 multishell 临时路径，不适合长期缓存
            # 使用临时文件 dot-source 替代 Out-String | Invoke-Expression 以减少解析开销
            $fnmInitFile = Join-Path ([System.IO.Path]::GetTempPath()) "fnm-init-$PID.ps1"
            try {
                fnm env --shell=power-shell --use-on-cd | Set-Content -Path $fnmInitFile -Encoding utf8NoBOM
                . $fnmInitFile
            }
            finally {
                Remove-Item -Path $fnmInitFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($tool in $tools.GetEnumerator()) {
        if ($availableTools.Contains($tool.Key)) {
            try {
                & $tool.Value
                Write-Verbose "成功初始化工具: $($tool.Key)"
            }
            catch {
                Write-Warning "初始化工具 $($tool.Key) 时出错: $($_.Exception.Message)"
            }
        }
        else {
            if (Test-ProfileInstallHintEligibility -ToolName $tool.Key -Platform $runtimePlatform -SkipTools:$SkipTools -SkipStarship:$SkipStarship -SkipZoxide:$SkipZoxide) {
                $missingHintToolNames.Add($tool.Key) | Out-Null
            }
            else {
                Write-Verbose "工具 $($tool.Key) 未安装，跳过初始化"
            }
        }
    }

    $missingToolHint = Get-ProfileMissingToolInstallHint -ToolNames $missingHintToolNames -AvailableCommands @($availableCommands) -Platform $runtimePlatform
    if ($missingToolHint) {
        Write-Host -ForegroundColor Yellow $missingToolHint.Message
        if (-not [string]::IsNullOrWhiteSpace($missingToolHint.Command)) {
            Write-Host -ForegroundColor Cyan $missingToolHint.Command
        }
    }

    if (-not $SkipAliases) { Set-AliasProfile }

    # z 函数懒加载：zoxide 已安装但未在初始化阶段加载时，首次调用自动初始化
    if (-not $Global:__ZoxideInitialized -and -not $SkipZoxide -and $availableTools.Contains('zoxide')) {
        $__zoxideCacheKey = "zoxide-init-powershell-$platformId"
        $__zoxideCacheDir = Join-Path $script:ProfileRoot '.cache'
        $zLazyBlock = {
            . (Invoke-WithFileCache -Key $__zoxideCacheKey -MaxAge ([TimeSpan]::FromDays(7)) -Generator { zoxide init powershell } -BaseDir $__zoxideCacheDir)
            Remove-Item function:Global:z -Force
            & z @args
        }.GetNewClosure()
        New-Item -Path "Function:Global:z" -Value $zLazyBlock -Force | Out-Null
    }

    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
    Write-Debug "PowerShell 环境初始化完成"
}
