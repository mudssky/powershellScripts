Set-StrictMode -Version Latest

<##
.SYNOPSIS
    读取必需 CLI 选项。
.PARAMETER Options
    已解析选项表。
.PARAMETER Name
    kebab-case 选项名。
.OUTPUTS
    System.Object
    返回选项值，不存在时抛错。
#>
function Get-BrowserDebugRequiredOption {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$Name)
    if (-not $Options.Contains($Name) -or [string]::IsNullOrWhiteSpace([string]$Options[$Name])) { throw "缺少必需选项: --$Name" }
    return $Options[$Name]
}

<##
.SYNOPSIS
    获取仓库根目录。
.OUTPUTS
    System.String
    返回 browser-debug 所在仓库根目录。
#>
function Get-BrowserDebugRepoRoot {
    [CmdletBinding()]
    param()
    return (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
}

<##
.SYNOPSIS
    获取默认 Profile 根目录。
.PARAMETER RegistryPath
    当前注册表路径，用于自定义注册表时推导可用根目录。
.OUTPUTS
    System.String
    返回 Profile 根目录。
#>
function Resolve-BrowserDebugProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryPath)
    if (-not [string]::IsNullOrWhiteSpace($env:BROWSER_DEBUG_ROOT_PATH)) { return [System.IO.Path]::GetFullPath($env:BROWSER_DEBUG_ROOT_PATH) }
    if ($RegistryPath -ne [System.IO.Path]::GetFullPath('D:\browser-debug-profiles\registry.json')) { return Split-Path -Parent $RegistryPath }
    return 'D:\browser-debug-profiles'
}

<##
.SYNOPSIS
    获取当前用户桌面路径。
.OUTPUTS
    System.String
    返回桌面目录。
#>
function Resolve-BrowserDebugDesktopPath {
    [CmdletBinding()]
    param()
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw '无法解析当前用户桌面目录。' }
    return $desktop
}

<##
.SYNOPSIS
    更新 Profile 的结构化快捷方式登记字段。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER Mode
    快捷方式模式 local 或 lan。
.PARAMETER ShortcutPath
    快捷方式绝对路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回更新后的 Profile，并保留 shortcutPath 作为 Local 兼容字段。
#>
function Set-BrowserDebugProfileShortcutRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][ValidateSet('local', 'lan')][string]$Mode,
        [Parameter(Mandatory)][string]$ShortcutPath
    )
    $localPath = if ($Mode -eq 'local') { $ShortcutPath } else { Get-BrowserDebugRegisteredShortcutPath -Profile $Profile -Mode local }
    $lanPath = if ($Mode -eq 'lan') { $ShortcutPath } else { Get-BrowserDebugRegisteredShortcutPath -Profile $Profile -Mode lan }
    $paths = [pscustomobject]@{ local = $localPath; lan = $lanPath }
    if ($Profile.PSObject.Properties['shortcutPaths']) { $Profile.shortcutPaths = $paths }
    else { $Profile | Add-Member -NotePropertyName shortcutPaths -NotePropertyValue $paths }
    if ($Profile.PSObject.Properties['shortcutPath']) { $Profile.shortcutPath = $localPath }
    else { $Profile | Add-Member -NotePropertyName shortcutPath -NotePropertyValue $localPath }
    $Profile.updatedAt = (Get-Date).ToString('o')
    return $Profile
}

<##
.SYNOPSIS
    创建新的浏览器调试 Profile。
.PARAMETER Name
    Profile 名称。
.PARAMETER Options
    CLI 选项表。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回新 Profile，不启动浏览器。
#>
function Invoke-BrowserDebugProfileCreate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    Assert-BrowserDebugName -Name $Name | Out-Null
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    if (Find-BrowserDebugProfile -Registry $registry -Name $Name) { throw "Profile 已存在: $Name" }
    $browser = [string](Get-BrowserDebugRequiredOption -Options $Options -Name 'browser')
    if ($browser -notin 'chrome', 'edge') { throw "不支持的浏览器: $browser" }
    $port = if ($Options.Contains('cdp-port')) { [int]$Options['cdp-port'] } else { 9222 }
    Assert-BrowserDebugPort -Port $port | Out-Null
    if (@($registry.profiles | Where-Object { [int]$_.cdpPort -eq $port }).Count -gt 0) { throw "CDP 端口已被其他 Profile 登记: $port" }
    $browserPath = Resolve-BrowserDebugExecutable -Browser $browser
    $defaultSourcePath = Resolve-BrowserDebugDefaultUserDataPath -Browser $browser
    $sourceUserDataPath = if ($Options.Contains('source-user-data-path')) { [System.IO.Path]::GetFullPath([string]$Options['source-user-data-path']) } else { $defaultSourcePath }
    $profileRoot = Resolve-BrowserDebugProfileRoot -RegistryPath $RegistryPath
    $profilePath = if ($Options.Contains('profile-path')) { [System.IO.Path]::GetFullPath([string]$Options['profile-path']) } else { Join-Path $profileRoot $Name }
    $profilePath = [System.IO.Path]::GetFullPath($profilePath)
    foreach ($registeredProfile in @($registry.profiles)) {
        if ([string]::IsNullOrWhiteSpace([string]$registeredProfile.profilePath)) { continue }
        if ([System.IO.Path]::GetFullPath([string]$registeredProfile.profilePath).Equals($profilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "目标 Profile 路径已被登记到 Profile $($registeredProfile.name): $profilePath"
        }
    }
    $defaultDataRoots = @(
        if ($browser -eq 'chrome') { Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' }
        if ($browser -eq 'edge') { Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($defaultRoot in $defaultDataRoots) {
        if ([System.IO.Path]::GetFullPath($profilePath).TrimEnd('\').Equals([System.IO.Path]::GetFullPath($defaultRoot).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw '禁止使用浏览器默认用户数据目录，必须使用独立 Profile 路径。'
        }
    }
    if ($profilePath.StartsWith('D:\', [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath 'D:\' -PathType Container)) {
        throw '默认 D 盘不存在；请使用 --profile-path 和 --registry-path 显式指定可用位置。'
    }
    if (Test-BrowserDebugPortOpen -Port $port) { throw "CDP 端口当前已被占用: $port" }
    $shortcutDirectory = if ($Options.Contains('shortcut-directory')) { [string]$Options['shortcut-directory'] } else { Resolve-BrowserDebugDesktopPath }
    $shortcutDirectory = [System.IO.Path]::GetFullPath($shortcutDirectory)
    $expectedShortcutPath = Join-Path $shortcutDirectory "$Name.lnk"
    if (Test-Path -LiteralPath $expectedShortcutPath) { throw "目标快捷方式已存在: $expectedShortcutPath" }

    $cloneCompleted = $false
    try {
        $cloneResult = Copy-BrowserDebugUserData `
            -BrowserPath $browserPath `
            -SourcePath $sourceUserDataPath `
            -DestinationPath $profilePath `
            -DefaultSourcePath $defaultSourcePath `
            -WithoutExtensions:([bool]$Options['without-extensions'])
        $cloneCompleted = $true
        $profile = [pscustomobject]@{
            name               = $Name
            browser            = $browser
            browserPath        = $browserPath
            cdpPort            = $port
            profilePath        = $profilePath
            sourceUserDataPath = $cloneResult.sourceUserDataPath
            extensionsCopied   = [bool]$cloneResult.extensionsCopied
            shortcutPath       = $null
            shortcutPaths      = [pscustomobject]@{ local = $null; lan = $null }
            createdAt          = (Get-Date).ToString('o')
            updatedAt          = (Get-Date).ToString('o')
        }
        $registry.profiles = @($registry.profiles) + $profile
        Add-BrowserDebugProfileShortcut -Profile $profile -Mode local -ShortcutDirectory $shortcutDirectory -RepoRoot (Get-BrowserDebugRepoRoot) -PersistScriptBlock {
            param($shortcutPath)
            Set-BrowserDebugProfileShortcutRegistration -Profile $profile -Mode local -ShortcutPath $shortcutPath | Out-Null
            Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
        } | Out-Null
        return $profile
    }
    catch {
        $creationError = $_
        $cleanupErrors = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $expectedShortcutPath -PathType Leaf) {
            try { Remove-Item -LiteralPath $expectedShortcutPath -Force -ErrorAction Stop }
            catch { $cleanupErrors.Add("快捷方式清理失败: $($_.Exception.Message)") }
        }
        if ($cloneCompleted -and (Test-Path -LiteralPath $profilePath -PathType Container)) {
            try { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction Stop }
            catch { $cleanupErrors.Add("Profile 目录清理失败: $($_.Exception.Message)") }
        }
        if ($cleanupErrors.Count -gt 0) {
            throw "创建 Profile 失败: $($creationError.Exception.Message)。$($cleanupErrors -join '；')"
        }
        throw $creationError
    }
}

<##
.SYNOPSIS
    更新停止状态的浏览器调试 Profile。
.PARAMETER Name
    Profile 名称。
.PARAMETER Options
    CLI 选项表。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回更新后的 Profile。
#>
function Invoke-BrowserDebugProfileSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $profile = Find-BrowserDebugProfile -Registry $registry -Name $Name
    if ($null -eq $profile) { throw "Profile 不存在: $Name" }
    $changesRuntimeConfiguration = $Options.Contains('cdp-port') -or $Options.Contains('browser')
    if ($changesRuntimeConfiguration -and (Get-BrowserDebugProfileRuntimeStatus -Profile $profile).running) { throw "Profile 正在运行，请先执行 profile stop $Name。" }
    if ($Options.Contains('cdp-port')) {
        $port = [int]$Options['cdp-port']; Assert-BrowserDebugPort -Port $port | Out-Null
        if (@($registry.profiles | Where-Object { $_.name -ne $Name -and [int]$_.cdpPort -eq $port }).Count -gt 0) { throw "CDP 端口已被其他 Profile 登记: $port" }
        if (Test-BrowserDebugPortOpen -Port $port) { throw "CDP 端口当前已被占用: $port" }
        $profile.cdpPort = $port
    }
    if ($Options.Contains('browser')) {
        $browser = [string]$Options['browser']; if ($browser -notin 'chrome', 'edge') { throw "不支持的浏览器: $browser" }
        $profile.browser = $browser
        $profile.browserPath = Resolve-BrowserDebugExecutable -Browser $browser
    }
    $profile.updatedAt = (Get-Date).ToString('o')
    if ($Options.Contains('shortcut-directory')) {
        Add-BrowserDebugProfileShortcut -Profile $profile -Mode local -ShortcutDirectory ([string]$Options['shortcut-directory']) -RepoRoot (Get-BrowserDebugRepoRoot) -PersistScriptBlock {
            param($shortcutPath)
            Set-BrowserDebugProfileShortcutRegistration -Profile $profile -Mode local -ShortcutPath $shortcutPath | Out-Null
            Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
        } | Out-Null
    }
    else { Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null }
    return $profile
}

<##
.SYNOPSIS
    为 Profile 创建或迁移指定模式的快捷方式。
.PARAMETER Name
    Profile 名称。
.PARAMETER Options
    CLI 选项表，必须包含 mode。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 Profile、模式和快捷方式路径。
#>
function Invoke-BrowserDebugProfileShortcut {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $profile = Find-BrowserDebugProfile -Registry $registry -Name $Name
    if ($null -eq $profile) { throw "Profile 不存在: $Name" }
    $mode = [string](Get-BrowserDebugRequiredOption -Options $Options -Name 'mode')
    if ($mode -notin 'local', 'lan') { throw "不支持的快捷方式模式: $mode" }
    $registeredPath = Get-BrowserDebugRegisteredShortcutPath -Profile $profile -Mode $mode
    $shortcutDirectory = if ($Options.Contains('shortcut-directory')) {
        [string]$Options['shortcut-directory']
    }
    elseif (-not [string]::IsNullOrWhiteSpace($registeredPath)) {
        Split-Path -Parent $registeredPath
    }
    else { Resolve-BrowserDebugDesktopPath }
    $shortcutPath = Add-BrowserDebugProfileShortcut -Profile $profile -Mode $mode -ShortcutDirectory $shortcutDirectory -RepoRoot (Get-BrowserDebugRepoRoot) -PersistScriptBlock {
        param($path)
        Set-BrowserDebugProfileShortcutRegistration -Profile $profile -Mode $mode -ShortcutPath $path | Out-Null
        Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
    }
    return [pscustomobject]@{ name = $Name; mode = $mode; shortcutPath = $shortcutPath }
}

<##
.SYNOPSIS
    查询一个或全部 Profile。
.PARAMETER Name
    可选 Profile 名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Object[]
    返回 Profile 集合。
#>
function Invoke-BrowserDebugProfileGet {
    [CmdletBinding()]
    param([string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace($Name)) { return , @($registry.profiles) }
    $profile = Find-BrowserDebugProfile -Registry $registry -Name $Name
    if ($null -eq $profile) { throw "Profile 不存在: $Name" }
    return $profile
}

<##
.SYNOPSIS
    启动浏览器调试 Profile。
.PARAMETER Name
    Profile 名称。
.PARAMETER Options
    CLI 选项表。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回启动结果。
#>
function Invoke-BrowserDebugProfileStart {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $profile = Find-BrowserDebugProfile -Registry $registry -Name $Name
    if ($null -eq $profile) { throw "Profile 不存在: $Name" }
    $mode = if ($Options.Contains('mode')) { [string]$Options['mode'] } else { 'local' }
    if ($mode -notin 'local', 'lan') { throw "不支持的启动模式: $mode" }
    if ($mode -eq 'local' -and $Options.Contains('listen-address')) { throw '--listen-address 只允许与 --mode lan 一起使用。' }
    $listenAddress = if ($Options.Contains('listen-address')) { Assert-BrowserDebugLanListenAddress -Address ([string]$Options['listen-address']) } else { $null }
    $openGuide = [bool]$Options['open-guide']
    $status = Get-BrowserDebugProfileRuntimeStatus -Profile $profile
    if ($status.running) {
        if (-not $openGuide) { throw "Profile 已在运行: $Name" }
        if ([string]::IsNullOrWhiteSpace([string]$status.mode) -or [string]$status.mode -ne $mode) {
            throw "Profile 当前以 $($status.mode) 模式运行，不能复用为 $mode；请先执行 profile stop $Name。"
        }
        if ($listenAddress -and [string]$status.listenAddress -ne $listenAddress) {
            throw "Profile 当前监听 $($status.listenAddress)，不能复用为 $listenAddress；请先执行 profile stop $Name。"
        }
        if (-not $status.cdpAvailable) { throw "Profile 进程正在运行，但 CDP 当前不可用: $($status.endpoint)" }
        $startResult = [pscustomobject]@{
            processId         = if ($status.PSObject.Properties['processId']) { $status.processId } elseif (@($status.processIds).Count -gt 0) { [int]$status.processIds[0] } else { $null }
            processIds        = @($status.processIds)
            launcherProcessId = $null
            cdpPort           = [int]$status.cdpPort
            mode              = [string]$status.mode
            listenAddress     = [string]$status.listenAddress
            endpoint          = [string]$status.endpoint
            cdpVersion        = $status.cdpVersion
            reused            = $true
        }
    }
    else {
        $startResult = Start-BrowserDebugProfileProcess -Profile $profile -Mode $mode -ListenAddress $listenAddress
        $startResult | Add-Member -NotePropertyName reused -NotePropertyValue $false -Force
    }
    if ($openGuide) {
        $warnings = [System.Collections.Generic.List[string]]::new()
        try {
            $snapshot = New-BrowserDebugGuideSnapshot -Profile $profile -StartResult $startResult -Registry $registry
            $guidePath = Write-BrowserDebugGuide -Snapshot $snapshot -RegistryPath $RegistryPath
            $startResult | Add-Member -NotePropertyName guidePath -NotePropertyValue $guidePath -Force
            try { Open-BrowserDebugGuide -Profile $profile -GuidePath $guidePath | Out-Null }
            catch { $warnings.Add("帮助页已生成但打开失败: $($_.Exception.Message)") }
        }
        catch { $warnings.Add("帮助页生成失败: $($_.Exception.Message)") }
        $startResult | Add-Member -NotePropertyName warnings -NotePropertyValue $warnings.ToArray() -Force
    }
    return $startResult
}

<##
.SYNOPSIS
    获取 Profile 实际状态。
.PARAMETER Name
    Profile 名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回实际状态。
#>
function Invoke-BrowserDebugProfileStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    return Get-BrowserDebugProfileRuntimeStatus -Profile (Invoke-BrowserDebugProfileGet -Name $Name -RegistryPath $RegistryPath)
}

<##
.SYNOPSIS
    停止 Profile 所属浏览器进程。
.PARAMETER Name
    Profile 名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回已停止 PID。
#>
function Invoke-BrowserDebugProfileStop {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $profile = Invoke-BrowserDebugProfileGet -Name $Name -RegistryPath $RegistryPath
    return [pscustomobject]@{ name = $Name; stoppedProcessIds = @(Stop-BrowserDebugProfileProcess -Profile $profile) }
}

<##
.SYNOPSIS
    创建 SSH 转发配置。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER Options
    CLI 选项表。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回新配置。
#>
function Invoke-BrowserDebugSshCreate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    Assert-BrowserDebugName -Name $Name | Out-Null
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    if (Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name) { throw "SSH 配置已存在: $Name" }
    $profileName = [string](Get-BrowserDebugRequiredOption -Options $Options -Name 'profile')
    if (-not (Find-BrowserDebugProfile -Registry $registry -Name $profileName)) { throw "关联 Profile 不存在: $profileName" }
    $direction = [string](Get-BrowserDebugRequiredOption -Options $Options -Name 'direction')
    if ($direction -notin 'local-forward', 'reverse-forward') { throw "不支持的转发方向: $direction" }
    $agentPort = [int](Get-BrowserDebugRequiredOption -Options $Options -Name 'agent-port'); Assert-BrowserDebugPort -Port $agentPort | Out-Null
    $configuration = [pscustomobject]@{
        name            = $Name
        profile         = $profileName
        direction       = $direction
        target          = [string](Get-BrowserDebugRequiredOption -Options $Options -Name 'target')
        agentPort       = $agentPort
        sshConfigPath   = if ($Options.Contains('ssh-config-path')) { [string]$Options['ssh-config-path'] } else { $null }
        verboseLogging  = [bool]$Options['verbose']
        reverseProcessId = $null
        createdAt       = (Get-Date).ToString('o')
        updatedAt       = (Get-Date).ToString('o')
    }
    $registry.sshConfigurations = @($registry.sshConfigurations) + $configuration
    Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
    return $configuration
}

<##
.SYNOPSIS
    更新 SSH 转发配置。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER Options
    CLI 选项表。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回更新后的配置。
#>
function Invoke-BrowserDebugSshSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][System.Collections.IDictionary]$Options, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $configuration = Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name
    if ($null -eq $configuration) { throw "SSH 配置不存在: $Name" }
    if ($configuration.reverseProcessId) {
        $recordedProcess = Get-BrowserDebugSshProcess -ProcessId ([int]$configuration.reverseProcessId)
        if ($recordedProcess) {
            $currentProfile = Find-BrowserDebugProfile -Registry $registry -Name ([string]$configuration.profile)
            $currentInfo = if ($currentProfile) { New-BrowserDebugSshInfo -Configuration $configuration -Profile $currentProfile } else { $null }
            if ($currentInfo -and (Test-BrowserDebugSshProcessOwnership -Process $recordedProcess -Info $currentInfo)) {
                throw "SSH 配置正在运行，请先执行 ssh stop $Name。"
            }
        }
        # PID 已退出或已被其他进程复用时只清理陈旧记录，不操作未知进程。
        $configuration.reverseProcessId = $null
    }
    if ($Options.Contains('profile')) {
        if (-not (Find-BrowserDebugProfile -Registry $registry -Name ([string]$Options['profile']))) { throw "关联 Profile 不存在: $($Options['profile'])" }
        $configuration.profile = [string]$Options['profile']
    }
    if ($Options.Contains('direction')) { if ([string]$Options['direction'] -notin 'local-forward', 'reverse-forward') { throw '无效 direction。' }; $configuration.direction = [string]$Options['direction'] }
    if ($Options.Contains('target')) { $configuration.target = [string]$Options['target'] }
    if ($Options.Contains('agent-port')) { $configuration.agentPort = Assert-BrowserDebugPort -Port ([int]$Options['agent-port']) }
    if ($Options.Contains('ssh-config-path')) { $configuration.sshConfigPath = [string]$Options['ssh-config-path'] }
    if ($Options.Contains('verbose')) { $configuration.verboseLogging = $true }
    if ($Options.Contains('no-verbose')) { $configuration.verboseLogging = $false }
    $configuration.updatedAt = (Get-Date).ToString('o')
    Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
    return $configuration
}

<##
.SYNOPSIS
    查询一个或全部 SSH 配置。
.PARAMETER Name
    可选 SSH 配置名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Object[]
    返回 SSH 配置集合。
#>
function Invoke-BrowserDebugSshGet {
    [CmdletBinding()]
    param([string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace($Name)) { return , @($registry.sshConfigurations) }
    $configuration = Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name
    if ($null -eq $configuration) { throw "SSH 配置不存在: $Name" }
    return $configuration
}

<##
.SYNOPSIS
    生成 SSH 配置的无副作用交接信息。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 Agent 交接对象。
#>
function Invoke-BrowserDebugSshInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $configuration = Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name
    if ($null -eq $configuration) { throw "SSH 配置不存在: $Name" }
    $profile = Find-BrowserDebugProfile -Registry $registry -Name ([string]$configuration.profile)
    if ($null -eq $profile) { throw "关联 Profile 不存在: $($configuration.profile)" }
    return New-BrowserDebugSshInfo -Configuration $configuration -Profile $profile
}

<##
.SYNOPSIS
    获取 SSH 配置运行状态。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回方向、PID 与所有权状态。
#>
function Invoke-BrowserDebugSshStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $configuration = Invoke-BrowserDebugSshGet -Name $Name -RegistryPath $RegistryPath
    $info = Invoke-BrowserDebugSshInfo -Name $Name -RegistryPath $RegistryPath
    $process = if ($configuration.reverseProcessId) { Get-BrowserDebugSshProcess -ProcessId ([int]$configuration.reverseProcessId) } else { $null }
    $owned = Test-BrowserDebugSshProcessOwnership -Process $process -Info $info
    return [pscustomobject]@{ name = $Name; direction = $configuration.direction; managedByWindows = $configuration.direction -eq 'reverse-forward'; running = $owned; owned = $owned; processId = $configuration.reverseProcessId; endpoint = $info.endpoint }
}

<##
.SYNOPSIS
    启动 reverse-forward SSH 配置。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 SSH PID 和 endpoint。
#>
function Invoke-BrowserDebugSshStart {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $configuration = Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name
    if ($null -eq $configuration) { throw "SSH 配置不存在: $Name" }
    $info = Invoke-BrowserDebugSshInfo -Name $Name -RegistryPath $RegistryPath
    if ($configuration.direction -eq 'local-forward') { throw "local-forward 不由 Windows 启动；请在远端 Agent 主机执行: $($info.sshCommand)" }
    if ((Invoke-BrowserDebugSshStatus -Name $Name -RegistryPath $RegistryPath).running) { throw "SSH 配置已在运行: $Name" }
    $configuration.reverseProcessId = Start-BrowserDebugSshProcess -Info $info
    $configuration.updatedAt = (Get-Date).ToString('o')
    try {
        Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
    }
    catch {
        $writeError = $_
        $startedProcess = Get-BrowserDebugSshProcess -ProcessId ([int]$configuration.reverseProcessId)
        if ($startedProcess -and (Test-BrowserDebugSshProcessOwnership -Process $startedProcess -Info $info)) {
            try { Stop-Process -Id ([int]$configuration.reverseProcessId) -Force -ErrorAction Stop }
            catch { throw "SSH 已启动但 registry 写入失败，且新进程清理失败: $($_.Exception.Message)。原始错误: $($writeError.Exception.Message)" }
        }
        throw $writeError
    }
    return [pscustomobject]@{ name = $Name; processId = $configuration.reverseProcessId; endpoint = $info.endpoint }
}

<##
.SYNOPSIS
    停止本工具拥有的 reverse-forward SSH 进程。
.PARAMETER Name
    SSH 配置名称。
.PARAMETER RegistryPath
    注册表路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回停止结果。
#>
function Invoke-BrowserDebugSshStop {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$RegistryPath)
    $registry = Read-BrowserDebugRegistry -RegistryPath $RegistryPath
    $configuration = Find-BrowserDebugSshConfiguration -Registry $registry -Name $Name
    if ($null -eq $configuration) { throw "SSH 配置不存在: $Name" }
    if ($configuration.direction -ne 'reverse-forward') { throw 'local-forward 由远端主机管理，Windows CLI 不停止该 SSH 会话。' }
    $info = Invoke-BrowserDebugSshInfo -Name $Name -RegistryPath $RegistryPath
    $process = if ($configuration.reverseProcessId) { Get-BrowserDebugSshProcess -ProcessId ([int]$configuration.reverseProcessId) } else { $null }
    if ($process -and -not (Test-BrowserDebugSshProcessOwnership -Process $process -Info $info)) { throw '记录的 PID 属于未知 SSH 进程，拒绝停止。' }
    if ($process) { Stop-Process -Id ([int]$configuration.reverseProcessId) -Force -ErrorAction Stop }
    $stoppedPid = $configuration.reverseProcessId
    $configuration.reverseProcessId = $null
    $configuration.updatedAt = (Get-Date).ToString('o')
    Write-BrowserDebugRegistry -RegistryPath $RegistryPath -Registry $registry | Out-Null
    return [pscustomobject]@{ name = $Name; stoppedProcessId = $stoppedPid }
}

<##
.SYNOPSIS
    分发已解析的业务命令。
.PARAMETER Parsed
    CLI 解析对象。
.OUTPUTS
    System.Object
    返回命令结果。
#>
function Invoke-BrowserDebugParsedCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Parsed)
    $registryPath = Resolve-BrowserDebugRegistryPath -RegistryPath ([string]$Parsed.Options['registry-path'])
    if ($Parsed.Resource -notin 'profile', 'ssh') { throw "未知资源: $($Parsed.Resource)" }
    if ([string]::IsNullOrWhiteSpace($Parsed.Action)) { throw "缺少动作: $($Parsed.Resource)" }
    if ($Parsed.Resource -eq 'profile') {
        switch ($Parsed.Action) {
            'create' { return Invoke-BrowserDebugProfileCreate -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
            'set' { return Invoke-BrowserDebugProfileSet -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
            'get' { return Invoke-BrowserDebugProfileGet -Name $Parsed.Name -RegistryPath $registryPath }
            'list' { return Invoke-BrowserDebugProfileGet -RegistryPath $registryPath }
            'start' { return Invoke-BrowserDebugProfileStart -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
            'status' { return Invoke-BrowserDebugProfileStatus -Name $Parsed.Name -RegistryPath $registryPath }
            'stop' { return Invoke-BrowserDebugProfileStop -Name $Parsed.Name -RegistryPath $registryPath }
            'shortcut' { return Invoke-BrowserDebugProfileShortcut -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
            default { throw "未知动作: profile $($Parsed.Action)" }
        }
    }
    switch ($Parsed.Action) {
        'create' { return Invoke-BrowserDebugSshCreate -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
        'set' { return Invoke-BrowserDebugSshSet -Name $Parsed.Name -Options $Parsed.Options -RegistryPath $registryPath }
        'get' { return Invoke-BrowserDebugSshGet -Name $Parsed.Name -RegistryPath $registryPath }
        'list' { return Invoke-BrowserDebugSshGet -RegistryPath $registryPath }
        'info' { return Invoke-BrowserDebugSshInfo -Name $Parsed.Name -RegistryPath $registryPath }
        'start' { return Invoke-BrowserDebugSshStart -Name $Parsed.Name -RegistryPath $registryPath }
        'status' { return Invoke-BrowserDebugSshStatus -Name $Parsed.Name -RegistryPath $registryPath }
        'stop' { return Invoke-BrowserDebugSshStop -Name $Parsed.Name -RegistryPath $registryPath }
        default { throw "未知动作: ssh $($Parsed.Action)" }
    }
}
