Set-StrictMode -Version Latest

<##
.SYNOPSIS
    验证当前平台支持 browser-debug 业务操作。
.OUTPUTS
    None
    非 Windows 平台抛出明确错误。
#>
function Assert-BrowserDebugWindowsPlatform {
    [CmdletBinding()]
    param()
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
        throw 'browser-debug 首版仅支持 Windows；帮助和 completion 可跨平台读取。'
    }
}

<##
.SYNOPSIS
    验证名称可安全用于目录和快捷方式。
.PARAMETER Name
    待验证名称。
.OUTPUTS
    System.String
    返回原始名称。
#>
function Assert-BrowserDebugName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Name -in '.', '..') {
        throw "名称无效: $Name"
    }
    return $Name
}

<##
.SYNOPSIS
    验证 TCP 端口范围。
.PARAMETER Port
    待验证端口。
.OUTPUTS
    System.Int32
    返回有效端口。
#>
function Assert-BrowserDebugPort {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Port)
    if ($Port -lt 1 -or $Port -gt 65535) { throw "端口必须位于 1..65535: $Port" }
    return $Port
}

<##
.SYNOPSIS
    发现 Chrome 或 Edge 可执行文件。
.PARAMETER Browser
    浏览器类型，支持 chrome 或 edge。
.OUTPUTS
    System.String
    返回浏览器可执行文件绝对路径。
#>
function Resolve-BrowserDebugExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('chrome', 'edge')][string]$Browser)

    $fileName = if ($Browser -eq 'chrome') { 'chrome.exe' } else { 'msedge.exe' }
    $relativePaths = if ($Browser -eq 'chrome') {
        @('Google\Chrome\Application\chrome.exe')
    }
    else { @('Microsoft\Edge\Application\msedge.exe') }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $roots) {
        foreach ($relativePath in $relativePaths) {
            $candidate = Join-Path $root $relativePath
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
        }
    }
    $command = Get-Command $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "未找到 $Browser 浏览器。请先安装浏览器，或确认其位于常见 Windows 安装目录。"
}

<##
.SYNOPSIS
    解析所选浏览器的默认 User Data 路径。
.PARAMETER Browser
    浏览器类型，支持 chrome 或 edge。
.OUTPUTS
    System.String
    返回当前用户的默认 User Data 绝对路径。
#>
function Resolve-BrowserDebugDefaultUserDataPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('chrome', 'edge')][string]$Browser)
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw '无法解析 LOCALAPPDATA，必须使用 --source-user-data-path 显式指定来源。' }
    $relativePath = if ($Browser -eq 'chrome') { 'Google\Chrome\User Data' } else { 'Microsoft\Edge\User Data' }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA $relativePath))
}

<##
.SYNOPSIS
    判断候选路径是否等于或位于父路径内。
.PARAMETER Path
    待检查路径。
.PARAMETER ParentPath
    父路径。
.OUTPUTS
    System.Boolean
    返回路径是否相同或存在包含关系。
#>
function Test-BrowserDebugPathWithin {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ParentPath)
    $candidate = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $parent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/')
    if ($candidate.Equals($parent, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith($parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

<##
.SYNOPSIS
    从 Chromium 命令行读取显式 user-data-dir。
.PARAMETER CommandLine
    浏览器进程命令行。
.OUTPUTS
    System.String
    返回 user-data-dir 路径，未声明时返回空值。
#>
function Get-BrowserDebugProcessUserDataPath {
    [CmdletBinding()]
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if ($CommandLine -match '(?:^|\s)--user-data-dir=(?:"(?<quoted>[^"]+)"|(?<plain>[^\s]+))') {
        $value = if ($Matches.quoted) { $Matches.quoted } else { $Matches.plain }
        return [System.IO.Path]::GetFullPath($value)
    }
    return $null
}

<##
.SYNOPSIS
    判断源 User Data 是否被对应浏览器进程使用。
.PARAMETER BrowserPath
    所选浏览器可执行文件路径。
.PARAMETER SourcePath
    待克隆 User Data 路径。
.PARAMETER DefaultSourcePath
    浏览器默认 User Data 路径。
.OUTPUTS
    System.Boolean
    返回源目录是否可能处于活动写入状态。
#>
function Test-BrowserDebugSourceInUse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BrowserPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DefaultSourcePath
    )
    $expectedExecutable = [System.IO.Path]::GetFullPath($BrowserPath)
    $source = [System.IO.Path]::GetFullPath($SourcePath)
    $defaultSource = [System.IO.Path]::GetFullPath($DefaultSourcePath)
    foreach ($process in @(Get-BrowserDebugChromiumProcesses)) {
        if ([string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) { continue }
        $actualExecutable = [System.IO.Path]::GetFullPath([string]$process.ExecutablePath)
        if (-not $actualExecutable.Equals($expectedExecutable, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $processUserDataPath = Get-BrowserDebugProcessUserDataPath -CommandLine ([string]$process.CommandLine)
        if ($processUserDataPath) {
            if ((Test-BrowserDebugPathWithin -Path $source -ParentPath $processUserDataPath) -or (Test-BrowserDebugPathWithin -Path $processUserDataPath -ParentPath $source)) { return $true }
            continue
        }
        if ($source.Equals($defaultSource, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

<##
.SYNOPSIS
    获取源 User Data 根目录中的 Chromium 锁文件。
.PARAMETER SourcePath
    User Data 来源目录。
.OUTPUTS
    System.IO.FileInfo[]
    返回会表明浏览器仍在运行或未正常关闭的锁文件。
#>
function Get-BrowserDebugSourceLockFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourcePath)
    $lockNames = @('SingletonCookie', 'SingletonLock', 'SingletonSocket', 'lockfile', 'DevToolsActivePort')
    return @($lockNames | ForEach-Object {
            $candidate = Join-Path $SourcePath $_
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
        })
}

<##
.SYNOPSIS
    执行可测试的 robocopy User Data 克隆。
.PARAMETER SourcePath
    来源 User Data 路径。
.PARAMETER DestinationPath
    临时目标路径。
.PARAMETER ExcludedFiles
    排除的锁文件和临时文件模式。
.PARAMETER ExcludedDirectories
    排除的运行时缓存与可选扩展目录名称。
.OUTPUTS
    System.Int32
    返回 robocopy 退出码，0..7 表示成功。
#>
function Invoke-BrowserDebugRobocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string[]]$ExcludedFiles = @(),
        [string[]]$ExcludedDirectories = @()
    )
    $arguments = @($SourcePath, $DestinationPath, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/XJ', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($ExcludedFiles.Count -gt 0) { $arguments += '/XF'; $arguments += $ExcludedFiles }
    if ($ExcludedDirectories.Count -gt 0) { $arguments += '/XD'; $arguments += $ExcludedDirectories }
    & robocopy.exe @arguments
    return $LASTEXITCODE
}

<##
.SYNOPSIS
    将现有 Chromium User Data 安全克隆到独立调试 Profile。
.PARAMETER BrowserPath
    所选浏览器可执行文件路径。
.PARAMETER SourcePath
    User Data 来源目录。
.PARAMETER DestinationPath
    registry 管理的最终 Profile 路径。
.PARAMETER DefaultSourcePath
    所选浏览器默认 User Data 路径。
.PARAMETER WithoutExtensions
    排除扩展本体和扩展状态目录以节省空间。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回来源、目标和扩展复制状态。
#>
function Copy-BrowserDebugUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BrowserPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$DefaultSourcePath,
        [switch]$WithoutExtensions
    )
    $source = [System.IO.Path]::GetFullPath($SourcePath)
    $destination = [System.IO.Path]::GetFullPath($DestinationPath)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "来源 User Data 目录不存在: $source" }
    if ((Test-BrowserDebugPathWithin -Path $destination -ParentPath $source) -or (Test-BrowserDebugPathWithin -Path $source -ParentPath $destination)) {
        throw '来源 User Data 与目标 Profile 不能相同或互相包含；目标必须是独立目录。'
    }
    if (Test-Path -LiteralPath $destination) { throw "目标 Profile 路径已存在，请使用空的新路径: $destination" }
    if (Test-BrowserDebugSourceInUse -BrowserPath $BrowserPath -SourcePath $source -DefaultSourcePath $DefaultSourcePath) {
        throw '来源浏览器仍在运行，继续复制可能产生不一致登录状态。请完全关闭浏览器后重试。'
    }
    $lockFiles = @(Get-BrowserDebugSourceLockFiles -SourcePath $source)
    if ($lockFiles.Count -gt 0) {
        throw "来源 User Data 存在 Chromium 锁文件: $($lockFiles.Name -join ', ')。请完全关闭浏览器后重试；若已关闭，请确认这些锁文件是否为异常退出残留。"
    }
    $parentDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    $temporaryPath = Join-Path $parentDirectory (".{0}.clone.{1}" -f ([System.IO.Path]::GetFileName($destination)), [guid]::NewGuid().ToString('N'))
    $excludedFiles = @('SingletonCookie', 'SingletonLock', 'SingletonSocket', 'lockfile', 'DevToolsActivePort', 'LOCK', 'LOCK-journal', '*.tmp', '*.temp')
    $excludedDirectories = @('BrowserMetrics', 'Crashpad', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache', 'DawnCache')
    if ($WithoutExtensions) {
        # Chromium 的扩展本体、扩展数据库与同步状态分散在多个同名目录，必须一起排除。
        $excludedDirectories += @('Extensions', 'Extension State', 'Local Extension Settings', 'Sync Extension Settings', 'Managed Extension Settings', 'Extension Rules', 'Extension Scripts', 'extensions_crx_cache')
    }
    try {
        $exitCode = Invoke-BrowserDebugRobocopy -SourcePath $source -DestinationPath $temporaryPath -ExcludedFiles $excludedFiles -ExcludedDirectories $excludedDirectories
        if ($exitCode -lt 0 -or $exitCode -gt 7) { throw "robocopy 克隆失败，退出码: $exitCode" }
        [System.IO.Directory]::Move($temporaryPath, $destination)
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    return [pscustomobject]@{ sourceUserDataPath = $source; profilePath = $destination; extensionsCopied = -not $WithoutExtensions }
}

<##
.SYNOPSIS
    判断端口是否正在监听。
.PARAMETER Port
    TCP 端口。
.PARAMETER Address
    可选目标地址，默认本机。
.OUTPUTS
    System.Boolean
    返回端口是否可建立连接。
#>
function Test-BrowserDebugPortOpen {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Port, [string]$Address = '127.0.0.1')
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($Address, $Port)
        return $task.Wait(250) -and $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
}

<##
.SYNOPSIS
    读取 CDP version endpoint。
.PARAMETER Port
    CDP 端口。
.PARAMETER Address
    探测地址。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 CDP version 对象，失败时返回空值。
#>
function Get-BrowserDebugCdpVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Port, [string]$Address = '127.0.0.1')
    try { return Invoke-RestMethod -Uri "http://${Address}:$Port/json/version" -TimeoutSec 1 -ErrorAction Stop }
    catch { return $null }
}

<##
.SYNOPSIS
    使用 ProcessStartInfo.ArgumentList detached 启动原生命令。
.PARAMETER FilePath
    可执行文件路径。
.PARAMETER Arguments
    原生命令参数数组。
.OUTPUTS
    System.Diagnostics.Process
    返回已启动进程对象。
#>
function Start-BrowserDebugDetachedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    return [System.Diagnostics.Process]::Start($startInfo)
}

<##
.SYNOPSIS
    获取可能由本工具启动的 Chromium 进程。
.OUTPUTS
    System.Object[]
    返回包含 PID、可执行文件和命令行的进程对象。
#>
function Get-BrowserDebugChromiumProcesses {
    [CmdletBinding()]
    param()
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) { return @() }
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue)
}

<##
.SYNOPSIS
    判断 Chromium 进程是否明确拥有目标 Profile。
.PARAMETER Process
    Win32_Process 对象。
.PARAMETER Profile
    Profile 注册对象。
.OUTPUTS
    System.Boolean
    返回进程可执行文件和 user-data-dir 是否同时匹配。
#>
function Test-BrowserDebugProcessOwnership {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Process, [Parameter(Mandatory)][object]$Profile)
    $expectedExecutable = [System.IO.Path]::GetFullPath([string]$Profile.browserPath)
    $actualExecutable = if ($Process.ExecutablePath) { [System.IO.Path]::GetFullPath([string]$Process.ExecutablePath) } else { '' }
    if (-not $actualExecutable.Equals($expectedExecutable, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    $profilePath = [System.IO.Path]::GetFullPath([string]$Profile.profilePath).TrimEnd('\')
    $escaped = [regex]::Escape($profilePath)
    return [string]$Process.CommandLine -match "(?:^|\s)--user-data-dir=(?:`"$escaped`"|$escaped)(?:\s|$)"
}

<##
.SYNOPSIS
    从 owned Chromium 进程中解析实际 CDP 绑定参数。
.PARAMETER Processes
    已确认拥有目标 Profile 的进程集合。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回实际主进程、CDP 端口、监听地址和模式；未找到完整绑定时返回空值。
#>
function Get-BrowserDebugRuntimeBinding {
    [CmdletBinding()]
    param([object[]]$Processes = @())
    foreach ($process in @($Processes)) {
        $commandLine = [string]$process.CommandLine
        if ($commandLine -notmatch '(?:^|\s)--remote-debugging-port=(?<port>\d+)(?:\s|$)') { continue }
        $port = [int]$Matches.port
        if ($port -lt 1 -or $port -gt 65535) { continue }
        if ($commandLine -notmatch '(?:^|\s)--remote-debugging-address=(?<address>[^\s"]+)(?:\s|$)') { continue }
        $address = [string]$Matches.address
        return [pscustomobject]@{
            process       = $process
            port          = $port
            listenAddress = $address
            mode          = if ($address -eq '127.0.0.1') { 'local' } else { 'lan' }
        }
    }
    return $null
}

<##
.SYNOPSIS
    验证 LAN 监听地址为可用的 IPv4 字面量。
.PARAMETER Address
    用户请求的 LAN 监听地址。
.OUTPUTS
    System.String
    返回规范化 IPv4 地址；拒绝回环、广播、组播和非 IPv4 输入。
#>
function Assert-BrowserDebugLanListenAddress {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "LAN 监听地址必须是 IPv4 字面量: $Address"
    }
    if ([System.Net.IPAddress]::IsLoopback($parsed) -or $parsed.Equals([System.Net.IPAddress]::Broadcast) -or $parsed.GetAddressBytes()[0] -ge 224) {
        throw "LAN 监听地址不能是回环、广播或组播地址: $Address"
    }
    return $parsed.ToString()
}

<##
.SYNOPSIS
    获取 Profile 的实际运行状态。
.PARAMETER Profile
    Profile 注册对象。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回所有权、CDP、端口和监听模式状态。
#>
function Get-BrowserDebugProfileRuntimeStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Profile)
    $owned = @(Get-BrowserDebugChromiumProcesses | Where-Object { Test-BrowserDebugProcessOwnership -Process $_ -Profile $Profile })
    $binding = Get-BrowserDebugRuntimeBinding -Processes $owned
    $actualPort = if ($binding) { [int]$binding.port } else { [int]$Profile.cdpPort }
    $listenAddress = if ($binding) { [string]$binding.listenAddress } else { $null }
    $mode = if ($binding) { [string]$binding.mode } else { $null }
    $probeAddress = if ($listenAddress -and $listenAddress -ne '0.0.0.0') { $listenAddress } else { '127.0.0.1' }
    $cdp = Get-BrowserDebugCdpVersion -Port $actualPort -Address $probeAddress
    $portOpen = Test-BrowserDebugPortOpen -Port $actualPort -Address $probeAddress
    return [pscustomobject]@{
        name          = $Profile.name
        running       = $owned.Count -gt 0
        owned         = $owned.Count -gt 0
        processId     = if ($binding) { [int]$binding.process.ProcessId } else { $null }
        processIds    = @($owned | ForEach-Object { [int]$_.ProcessId })
        portOpen      = $portOpen
        cdpAvailable  = $null -ne $cdp
        cdpPort       = $actualPort
        mode          = $mode
        listenAddress = $listenAddress
        endpoint      = "http://${probeAddress}:$actualPort"
        cdpVersion    = $cdp
    }
}

<##
.SYNOPSIS
    detached 启动浏览器并等待 CDP 可用。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER Mode
    监听模式 local 或 lan。
.PARAMETER ListenAddress
    lan 模式可选监听地址。
.PARAMETER StartupTimeoutSeconds
    等待目标 Profile 进程和 CDP 同时就绪的超时秒数。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回拥有目标 Profile 的 PID、launcher PID、endpoint 和监听信息。
#>
function Start-BrowserDebugProfileProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [ValidateSet('local', 'lan')][string]$Mode = 'local',
        [string]$ListenAddress,
        [ValidateRange(1, 60)][int]$StartupTimeoutSeconds = 10
    )
    $status = Get-BrowserDebugProfileRuntimeStatus -Profile $Profile
    if ($status.running) { throw "Profile 已在运行: $($Profile.name)" }
    if ($status.portOpen) { throw "CDP 端口已被未知进程占用: $($Profile.cdpPort)" }
    $address = if ($Mode -eq 'local') { '127.0.0.1' } elseif ([string]::IsNullOrWhiteSpace($ListenAddress)) { '0.0.0.0' } else { Assert-BrowserDebugLanListenAddress -Address $ListenAddress }
    $probeAddress = if ($address -eq '0.0.0.0') { '127.0.0.1' } else { $address }
    $browserArguments = @(
        "--user-data-dir=$($Profile.profilePath)",
        "--remote-debugging-port=$($Profile.cdpPort)",
        "--remote-debugging-address=$address",
        '--no-first-run',
        '--no-default-browser-check'
    )
    $process = Start-BrowserDebugDetachedProcess -FilePath ([string]$Profile.browserPath) -Arguments $browserArguments
    if ($null -eq $process) { throw '浏览器进程启动失败。' }
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $launcherExitCode = $null
    do {
        Start-Sleep -Milliseconds 200
        $version = Get-BrowserDebugCdpVersion -Port ([int]$Profile.cdpPort) -Address $probeAddress
        $ownedProcesses = @(Get-BrowserDebugChromiumProcesses | Where-Object { Test-BrowserDebugProcessOwnership -Process $_ -Profile $Profile })
        $binding = Get-BrowserDebugRuntimeBinding -Processes $ownedProcesses
        if ($null -ne $version -and $ownedProcesses.Count -gt 0 -and $binding) {
            $actualProbeAddress = if ([string]$binding.listenAddress -eq '0.0.0.0') { '127.0.0.1' } else { [string]$binding.listenAddress }
            return [pscustomobject]@{
                processId        = [int]$binding.process.ProcessId
                processIds       = @($ownedProcesses | ForEach-Object { [int]$_.ProcessId })
                launcherProcessId = $process.Id
                cdpPort          = [int]$binding.port
                mode             = [string]$binding.mode
                listenAddress    = [string]$binding.listenAddress
                endpoint         = "http://${actualProbeAddress}:$($binding.port)"
                cdpVersion       = $version
            }
        }
        if ($process.HasExited) {
            $launcherExitCode = $process.ExitCode
            # Edge 的 launcher 可正常退出 0 并由子进程接管；只有非零退出且没有任何接管证据时才快速失败。
            if ($launcherExitCode -ne 0 -and $null -eq $version -and $ownedProcesses.Count -eq 0) {
                throw "浏览器启动器异常退出，退出码: $launcherExitCode，且未发现目标 Profile 进程或 CDP。"
            }
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -ne $launcherExitCode) {
        throw "浏览器启动器已退出，退出码: $launcherExitCode，但目标 Profile 进程和 CDP 未在超时内同时就绪: http://127.0.0.1:$($Profile.cdpPort)/json/version"
    }
    throw "浏览器已启动，但目标 Profile 进程和 CDP 未在超时内同时就绪: http://127.0.0.1:$($Profile.cdpPort)/json/version"
}

<##
.SYNOPSIS
    只停止明确拥有目标 Profile 的浏览器进程。
.PARAMETER Profile
    Profile 注册对象。
.OUTPUTS
    System.Int32[]
    返回停止前确认拥有目标 Profile、并实际请求停止的进程 PID。
#>
function Stop-BrowserDebugProfileProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Profile)
    $owned = @(Get-BrowserDebugChromiumProcesses | Where-Object { Test-BrowserDebugProcessOwnership -Process $_ -Profile $Profile })
    foreach ($process in $owned) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop }
        catch {
            $alreadyExited = $_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound -and
                $_.FullyQualifiedErrorId.StartsWith('NoProcessFoundForGivenId', [System.StringComparison]::Ordinal)
            if ($alreadyExited) { continue }
            throw
        }
    }
    return @($owned | ForEach-Object { [int]$_.ProcessId })
}

<##
.SYNOPSIS
    创建 Profile 桌面快捷方式。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER ShortcutDirectory
    快捷方式目录。
.PARAMETER RepoRoot
    仓库根目录。
.PARAMETER Mode
    快捷方式启动模式，支持 local 或 lan。
.PARAMETER ShortcutPath
    可选的精确输出路径，事务层使用临时 `.lnk` 时传入。
.OUTPUTS
    System.String
    返回快捷方式路径。
#>
function New-BrowserDebugShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][string]$ShortcutDirectory,
        [Parameter(Mandatory)][string]$RepoRoot,
        [ValidateSet('local', 'lan')][string]$Mode = 'local',
        [string]$ShortcutPath
    )
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
    $modulePath = Join-Path $RepoRoot 'psutils/modules/win.psm1'
    Import-Module $modulePath -Force -ErrorAction Stop
    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $entryPath = Join-Path $RepoRoot 'bin/browser-debug.ps1'
    if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) { $entryPath = Join-Path $RepoRoot 'scripts/pwsh/devops/browser-debug/main.ps1' }
    if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
        $shortcutName = if ($Mode -eq 'lan') { "$($Profile.name)-LAN.lnk" } else { "$($Profile.name).lnk" }
        $ShortcutPath = Join-Path $ShortcutDirectory $shortcutName
    }
    $arguments = "-NoProfile -File `"$entryPath`" profile start `"$($Profile.name)`" --mode $Mode --open-guide --yes"
    New-Shortcut -TargetPath $pwshPath -ShortcutPath $ShortcutPath -Arguments $arguments -WorkingDirectory $RepoRoot -IconLocation $Profile.browserPath
    return $ShortcutPath
}

<##
.SYNOPSIS
    获取 Profile 已登记的指定模式快捷方式路径。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER Mode
    快捷方式模式 local 或 lan。
.OUTPUTS
    System.String
    返回结构化路径；旧 registry 的 local 模式回退到 shortcutPath。
#>
function Get-BrowserDebugRegisteredShortcutPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Profile, [Parameter(Mandatory)][ValidateSet('local', 'lan')][string]$Mode)
    $shortcutPathsProperty = $Profile.PSObject.Properties['shortcutPaths']
    if ($shortcutPathsProperty -and $null -ne $shortcutPathsProperty.Value) {
        $modeProperty = $shortcutPathsProperty.Value.PSObject.Properties[$Mode]
        if ($modeProperty -and -not [string]::IsNullOrWhiteSpace([string]$modeProperty.Value)) { return [string]$modeProperty.Value }
        if ($shortcutPathsProperty.Value -is [System.Collections.IDictionary] -and -not [string]::IsNullOrWhiteSpace([string]$shortcutPathsProperty.Value[$Mode])) {
            return [string]$shortcutPathsProperty.Value[$Mode]
        }
    }
    if ($Mode -eq 'local') {
        $legacyProperty = $Profile.PSObject.Properties['shortcutPath']
        if ($legacyProperty -and -not [string]::IsNullOrWhiteSpace([string]$legacyProperty.Value)) { return [string]$legacyProperty.Value }
    }
    return $null
}

<##
.SYNOPSIS
    检查已登记快捷方式是否符合当前启动合同。
.PARAMETER ShortcutPath
    快捷方式绝对路径。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER Mode
    快捷方式模式 local 或 lan。
.OUTPUTS
    System.Boolean
    参数包含目标 Profile、模式、帮助页和免确认切换选项时返回 true。
#>
function Test-BrowserDebugShortcutCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][ValidateSet('local', 'lan')][string]$Mode
    )
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) { return $false }
    try {
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($ShortcutPath)
        $arguments = [string]$shortcut.Arguments
        $profilePattern = [regex]::Escape([string]$Profile.name)
        $modePattern = [regex]::Escape($Mode)
        return $arguments -match ('profile start\s+"?' + $profilePattern + '"?(?:\s|$)') -and
            $arguments -match ('--mode\s+' + $modePattern + '(?:\s|$)') -and
            $arguments -match '(?:^|\s)--open-guide(?:\s|$)' -and
            $arguments -match '(?:^|\s)--yes(?:\s|$)'
    }
    catch { return $false }
}

<##
.SYNOPSIS
    事务式创建或迁移单个模式的 Profile 快捷方式。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER Mode
    快捷方式模式 local 或 lan。
.PARAMETER ShortcutDirectory
    目标快捷方式目录。
.PARAMETER RepoRoot
    仓库根目录。
.PARAMETER PersistScriptBlock
    文件就绪后持久化 registry 的回调，接收最终路径。
.OUTPUTS
    System.String
    返回已登记或新创建的快捷方式路径。
#>
function Add-BrowserDebugProfileShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][ValidateSet('local', 'lan')][string]$Mode,
        [Parameter(Mandatory)][string]$ShortcutDirectory,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][scriptblock]$PersistScriptBlock
    )
    $directory = [System.IO.Path]::GetFullPath($ShortcutDirectory)
    $fileName = if ($Mode -eq 'lan') { "$($Profile.name)-LAN.lnk" } else { "$($Profile.name).lnk" }
    $finalPath = Join-Path $directory $fileName
    $registeredPath = Get-BrowserDebugRegisteredShortcutPath -Profile $Profile -Mode $Mode
    $registeredMatches = -not [string]::IsNullOrWhiteSpace($registeredPath) -and
        [System.IO.Path]::GetFullPath($registeredPath).Equals($finalPath, [System.StringComparison]::OrdinalIgnoreCase)
    $shortcutPathsProperty = $Profile.PSObject.Properties['shortcutPaths']
    $hasStructuredRegistration = $false
    if ($shortcutPathsProperty -and $null -ne $shortcutPathsProperty.Value) {
        if ($shortcutPathsProperty.Value -is [System.Collections.IDictionary]) {
            $hasStructuredRegistration = -not [string]::IsNullOrWhiteSpace([string]$shortcutPathsProperty.Value[$Mode])
        }
        else {
            $modeProperty = $shortcutPathsProperty.Value.PSObject.Properties[$Mode]
            $hasStructuredRegistration = $modeProperty -and -not [string]::IsNullOrWhiteSpace([string]$modeProperty.Value)
        }
    }
    if ($registeredMatches -and $hasStructuredRegistration -and (Test-BrowserDebugShortcutCurrent -ShortcutPath $finalPath -Profile $Profile -Mode $Mode)) { return $finalPath }
    if ((Test-Path -LiteralPath $finalPath -PathType Leaf) -and -not $registeredMatches) { throw "目标快捷方式已存在但未由该 Profile 登记: $finalPath" }

    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $transactionId = [guid]::NewGuid().ToString('N')
    $temporaryPath = Join-Path $directory (".$fileName.$transactionId.tmp.lnk")
    $backupPath = $null
    $promoted = $false
    try {
        New-BrowserDebugShortcut -Profile $Profile -ShortcutDirectory $directory -RepoRoot $RepoRoot -Mode $Mode -ShortcutPath $temporaryPath | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($registeredPath) -and (Test-Path -LiteralPath $registeredPath -PathType Leaf)) {
            $backupPath = "$registeredPath.$transactionId.bak"
            Move-Item -LiteralPath $registeredPath -Destination $backupPath -ErrorAction Stop
        }
        Move-Item -LiteralPath $temporaryPath -Destination $finalPath -ErrorAction Stop
        $promoted = $true
        & $PersistScriptBlock $finalPath | Out-Null
        # registry 已提交后，历史备份清理失败不应把文件回滚到旧路径造成状态不一致。
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
        return $finalPath
    }
    catch {
        $transactionError = $_
        if ($promoted -and (Test-Path -LiteralPath $finalPath)) { Remove-Item -LiteralPath $finalPath -Force -ErrorAction SilentlyContinue }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) { Move-Item -LiteralPath $backupPath -Destination $registeredPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        throw $transactionError
    }
}

<##
.SYNOPSIS
    获取当前可用于局域网连接的 IPv4 地址。
.OUTPUTS
    System.String[]
    返回已启用网卡的非回环、非 APIPA IPv4 地址。
#>
function Get-BrowserDebugLanIPv4Addresses {
    [CmdletBinding()]
    param()
    return @(
        [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            ForEach-Object { $_.Address } |
            Where-Object {
                $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not [System.Net.IPAddress]::IsLoopback($_) -and
                -not $_.ToString().StartsWith('169.254.', [System.StringComparison]::Ordinal)
            } |
            ForEach-Object { $_.ToString() } |
            Sort-Object -Unique
    )
}

<##
.SYNOPSIS
    构造启动帮助页使用的不可变快照。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER StartResult
    本次启动或复用的实际运行结果。
.PARAMETER Registry
    当前 registry，用于解析关联 SSH 配置。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回不包含浏览器敏感数据的帮助页快照。
#>
function New-BrowserDebugGuideSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][object]$StartResult,
        [Parameter(Mandatory)][object]$Registry
    )
    $lanAddresses = @(Get-BrowserDebugLanIPv4Addresses)
    $actualPort = if ($StartResult.PSObject.Properties['cdpPort']) { [int]$StartResult.cdpPort } else { [int]$Profile.cdpPort }
    $endpointHost = if ([string]$StartResult.mode -eq 'lan' -and [string]$StartResult.listenAddress -ne '0.0.0.0') { [string]$StartResult.listenAddress } else { '127.0.0.1' }
    $endpoint = "http://${endpointHost}:$actualPort"
    $directAddresses = if ([string]$StartResult.mode -ne 'lan') {
        @()
    }
    elseif ([string]$StartResult.listenAddress -ne '0.0.0.0') {
        @([string]$StartResult.listenAddress)
    }
    else { @($lanAddresses) }
    $directConnections = @($directAddresses | ForEach-Object {
            $directEndpoint = "http://${_}:$actualPort"
            [pscustomobject]@{
                address           = [string]$_
                endpoint          = $directEndpoint
                probeUrl          = "$directEndpoint/json/version"
                playwrightCommand = "playwright-cli attach --cdp=$directEndpoint"
                agentPrompt       = "请连接现有浏览器，不要创建新的浏览器实例。先确认 $directEndpoint/json/version 可访问，然后执行 ``playwright-cli attach --cdp=$directEndpoint``。"
            }
        })
    $snapshotProfile = $Profile.PSObject.Copy()
    $snapshotProfile.cdpPort = $actualPort
    $sshInfo = @(
        $Registry.sshConfigurations |
            Where-Object { [string]$_.profile -eq [string]$Profile.name } |
            ForEach-Object { New-BrowserDebugSshInfo -Configuration $_ -Profile $snapshotProfile }
    )
    $cdpBrowser = if ($StartResult.cdpVersion -and $StartResult.cdpVersion.PSObject.Properties['Browser']) { [string]$StartResult.cdpVersion.Browser } else { $null }
    return [pscustomobject]@{
        generatedAt       = (Get-Date).ToString('o')
        name              = [string]$Profile.name
        browser           = [string]$Profile.browser
        profilePath       = [string]$Profile.profilePath
        cdpPort           = $actualPort
        mode              = [string]$StartResult.mode
        listenAddress     = [string]$StartResult.listenAddress
        endpoint          = $endpoint
        probeUrl          = "$endpoint/json/version"
        playwrightCommand = "playwright-cli attach --cdp=$endpoint"
        cdpVersion        = $cdpBrowser
        lanAddresses      = $lanAddresses
        directConnections = $directConnections
        sshConfigurations = $sshInfo
        agentPrompt       = if ($directConnections.Count -gt 1) {
            '请连接现有浏览器，不要创建新的浏览器实例。请从页面列出的 LAN IPv4 直连项中选择远端可达地址，再使用对应的探测 URL 和 playwright-cli attach 命令。'
        }
        else { "请连接现有浏览器，不要创建新的浏览器实例。先确认 $endpoint/json/version 可访问，然后执行 ``playwright-cli attach --cdp=$endpoint``。" }
    }
}

<##
.SYNOPSIS
    将帮助页快照渲染为静态 HTML。
.PARAMETER Snapshot
    启动帮助页快照。
.OUTPUTS
    System.String
    返回已对全部动态内容进行 HTML 编码的页面文本。
#>
function ConvertTo-BrowserDebugGuideHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Snapshot)
    $encode = { param([object]$Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
    $copyField = {
        param([string]$Label, [string]$Value, [string]$Tone = 'default')
        $encodedLabel = & $encode $Label
        $encodedValue = & $encode $Value
        return @"
<div class="command-field command-$Tone">
<div class="command-label">$encodedLabel</div>
<div class="copy-field"><code>$encodedValue</code><button class="copy-button" type="button" data-copy="$encodedValue" title="复制 $encodedLabel" aria-label="复制 $encodedLabel"><svg aria-hidden="true"><use href="#icon-copy"></use></svg></button></div>
</div>
"@
    }

    $lanRows = [System.Collections.Generic.List[string]]::new()
    foreach ($connection in @($Snapshot.directConnections)) {
        $address = & $encode $connection.address
        $lanRows.Add(@"
<article class="connection-item">
<div class="connection-heading"><span class="connection-address">$address</span><span class="semantic-tag tag-lan">LAN IPv4</span></div>
$(& $copyField 'CDP endpoint' ([string]$connection.endpoint) 'connect')
$(& $copyField '探测地址' ([string]$connection.probeUrl))
$(& $copyField 'Playwright attach' ([string]$connection.playwrightCommand))
</article>
"@)
    }

    $sshRows = [System.Collections.Generic.List[string]]::new()
    foreach ($ssh in @($Snapshot.sshConfigurations)) {
        $sshName = & $encode $ssh.name
        $sshFields = [System.Collections.Generic.List[string]]::new()
        $sshFields.Add((& $copyField 'SSH 命令' ([string]$ssh.sshCommand) 'ssh'))
        $sshEndpoint = $ssh.PSObject.Properties['endpoint']
        $sshProbeUrl = $ssh.PSObject.Properties['probeUrl']
        $sshPlaywrightCommand = $ssh.PSObject.Properties['playwrightCommand']
        if ($sshEndpoint -and -not [string]::IsNullOrWhiteSpace([string]$sshEndpoint.Value)) { $sshFields.Add((& $copyField 'CDP endpoint' ([string]$sshEndpoint.Value) 'connect')) }
        if ($sshProbeUrl -and -not [string]::IsNullOrWhiteSpace([string]$sshProbeUrl.Value)) { $sshFields.Add((& $copyField '探测地址' ([string]$sshProbeUrl.Value))) }
        if ($sshPlaywrightCommand -and -not [string]::IsNullOrWhiteSpace([string]$sshPlaywrightCommand.Value)) { $sshFields.Add((& $copyField 'Playwright attach' ([string]$sshPlaywrightCommand.Value))) }
        $sshRows.Add(@"
<article class="connection-item">
<div class="connection-heading"><span class="connection-address">$sshName</span><span class="semantic-tag tag-ssh">SSH</span></div>
$($sshFields -join [Environment]::NewLine)
</article>
"@)
    }

    $promptRows = [System.Collections.Generic.List[string]]::new()
    $promptRows.Add((& $copyField '通用 Agent Prompt' ([string]$Snapshot.agentPrompt) 'prompt'))
    foreach ($connection in @($Snapshot.directConnections)) {
        $promptRows.Add((& $copyField "LAN $($connection.address)" ([string]$connection.agentPrompt) 'prompt'))
    }
    foreach ($ssh in @($Snapshot.sshConfigurations)) {
        $promptRows.Add((& $copyField "SSH $($ssh.name)" ([string]$ssh.agentPrompt) 'prompt'))
    }

    $mode = & $encode $Snapshot.mode
    $name = & $encode $Snapshot.name
    $browser = & $encode $Snapshot.browser
    $profilePath = & $encode $Snapshot.profilePath
    $listenAddress = & $encode $Snapshot.listenAddress
    $cdpVersion = & $encode $Snapshot.cdpVersion
    $generatedAt = & $encode $Snapshot.generatedAt
    $cdpPort = & $encode $Snapshot.cdpPort
    $lanAddresses = & $encode (@($Snapshot.lanAddresses) -join ', ')
    $modeLabel = if ([string]$Snapshot.mode -eq 'lan') { 'LAN 调试' } else { '本机调试' }
    $warning = if ([string]$Snapshot.mode -eq 'lan') {
        '<aside class="risk-notice" role="note"><div class="risk-icon" aria-hidden="true">!</div><div><strong>LAN 安全警告</strong><p>CDP 没有认证，同一网络中的可达主机可以完全控制此浏览器。本工具不会自动配置 Windows 防火墙，请仅在受控网络开放。</p></div></aside>'
    }
    else { '' }
    $lanSection = if ($lanRows.Count -gt 0) {
        "<section class=`"scenario-section lan-section`"><div class=`"section-heading`"><div><span class=`"section-kicker`">局域网直连</span><h2>LAN endpoints</h2></div><span class=`"section-count`">$($lanRows.Count) 个地址</span></div><div class=`"connection-list`">$($lanRows -join [Environment]::NewLine)</div></section>"
    }
    else { '' }
    $sshSection = if ($sshRows.Count -gt 0) {
        "<section class=`"scenario-section ssh-section`"><div class=`"section-heading`"><div><span class=`"section-kicker`">远程转发</span><h2>SSH configurations</h2></div><span class=`"section-count`">$($sshRows.Count) 个配置</span></div><div class=`"connection-list`">$($sshRows -join [Environment]::NewLine)</div></section>"
    }
    else { '' }
    return @"
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>browser-debug - $name</title>
<style>:root{color-scheme:light;--page:#f3f5f7;--surface:#ffffff;--surface-muted:#f8fafb;--text:#17212b;--muted:#5f6b76;--border:#d9e0e6;--green:#17824f;--green-soft:#e9f7ef;--cyan:#087f8c;--cyan-soft:#e7f7f8;--amber:#a15c00;--amber-soft:#fff4df;--red:#b23a3a;--red-soft:#fff0f0;--focus:#0b6bcb;--shadow:0 1px 2px rgba(23,33,43,.06)}*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--text);font-family:"Segoe UI",Arial,sans-serif;font-size:14px;line-height:1.5;letter-spacing:0}.shell{width:min(1180px,calc(100% - 32px));margin:24px auto 48px}.app-header{margin-bottom:16px;min-width:0}.brand-line{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:8px}.brand{font-size:14px;font-weight:700;color:var(--cyan)}.running-badge{display:inline-flex;align-items:center;gap:7px;color:var(--green);font-weight:600;background:var(--green-soft);border:1px solid #b9e2ca;padding:4px 9px;border-radius:6px}.status-dot{width:8px;height:8px;border-radius:50%;background:var(--green)}h1{font-size:28px;line-height:1.2;margin:0 0 5px;font-weight:680;overflow-wrap:anywhere}h1 span{color:var(--muted);font-weight:500}.subtitle{margin:0;color:var(--muted);overflow-wrap:anywhere}.status-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1px;background:var(--border);border:1px solid var(--border);border-radius:8px;overflow:hidden;box-shadow:var(--shadow);margin-bottom:16px}.status-item{background:var(--surface);padding:13px 15px;min-width:0}.status-label,.section-kicker,.command-label,.meta-label{display:block;color:var(--muted);font-size:12px;font-weight:650}.status-value{display:block;margin-top:3px;font-size:15px;font-weight:650;overflow-wrap:anywhere}.content-grid{display:grid;grid-template-columns:minmax(0,1.6fr) minmax(280px,.8fr);gap:16px;align-items:start}.tool-panel,.scenario-section{background:var(--surface);border:1px solid var(--border);border-radius:8px;box-shadow:var(--shadow);min-width:0}.quick-connect{padding:20px;border-top:3px solid var(--cyan)}.panel-heading,.section-heading{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:16px}.panel-heading h2,.section-heading h2{font-size:18px;margin:2px 0 0}.semantic-tag,.section-count{display:inline-flex;align-items:center;white-space:nowrap;border-radius:6px;padding:3px 8px;font-size:12px;font-weight:650}.tag-connect{color:var(--cyan);background:var(--cyan-soft)}.tag-lan{color:var(--amber);background:var(--amber-soft)}.tag-ssh{color:#3756a3;background:#edf1ff}.command-field{min-width:0}.command-field+.command-field{margin-top:12px}.command-label{margin-bottom:5px}.copy-field{display:grid;grid-template-columns:minmax(0,1fr) 36px;border:1px solid var(--border);border-radius:6px;overflow:hidden;background:var(--surface-muted);min-width:0}.command-connect .copy-field{border-color:#9fd6db;background:var(--cyan-soft)}.command-ssh .copy-field{border-color:#c9d2ef;background:#f3f5ff}.command-prompt .copy-field{border-color:#d8c7ef;background:#faf7ff}.copy-field code{display:block;padding:10px 12px;color:var(--text);font:13px/1.55 Consolas,"Courier New",monospace;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;min-width:0}.copy-button{display:grid;place-items:center;width:36px;min-height:36px;padding:0;border:0;border-left:1px solid var(--border);background:var(--surface);color:var(--muted);cursor:pointer}.copy-button svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}.copy-button:hover{color:var(--cyan);background:#eef8f9}.copy-button:focus-visible{outline:3px solid var(--focus);outline-offset:-3px}.copy-button.is-copied{color:var(--green);background:var(--green-soft)}.metadata-panel{padding:20px}.metadata-grid{display:grid;grid-template-columns:1fr;gap:0;margin:0}.meta-row{padding:10px 0;border-bottom:1px solid #edf0f2;min-width:0}.meta-row:last-child{border-bottom:0}.meta-value{display:block;margin-top:2px;font-weight:550;overflow-wrap:anywhere}.risk-notice{display:flex;gap:12px;align-items:flex-start;margin:16px 0;padding:13px 15px;border:1px solid #efc589;border-left:4px solid var(--amber);border-radius:6px;background:var(--amber-soft);color:#613c08}.risk-notice p{margin:2px 0 0;color:#72511f}.risk-icon{display:grid;place-items:center;flex:0 0 24px;height:24px;border-radius:50%;background:var(--amber);color:#fff;font-weight:800}.scenario-stack{display:grid;gap:16px;margin-top:16px}.scenario-section{padding:20px}.lan-section{border-top:3px solid var(--amber)}.ssh-section{border-top:3px solid #536fb5}.agent-section{border-top:3px solid #7b5aa6}.connection-list{display:grid;gap:18px}.connection-item{min-width:0}.connection-item+.connection-item{padding-top:18px;border-top:1px solid var(--border)}.connection-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:11px}.connection-address{font-weight:700;overflow-wrap:anywhere}.icon-sprite{position:absolute;width:0;height:0;overflow:hidden}.toast{position:fixed;right:20px;bottom:20px;z-index:10;max-width:min(360px,calc(100% - 32px));padding:10px 14px;border-radius:6px;background:#17212b;color:#fff;box-shadow:0 8px 24px rgba(23,33,43,.18);opacity:0;transform:translateY(8px);pointer-events:none;transition:opacity .15s ease,transform .15s ease}.toast.is-visible{opacity:1;transform:translateY(0)}@media(max-width:900px){.status-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.content-grid{grid-template-columns:1fr}}@media(max-width:720px){.shell{width:min(100% - 20px,1180px);margin-top:14px}.brand-line,.panel-heading,.section-heading,.connection-heading{align-items:flex-start}.status-grid{grid-template-columns:1fr 1fr}.quick-connect,.metadata-panel,.scenario-section{padding:15px}h1{font-size:23px}.copy-field code{font-size:12px;padding:9px 10px}}@media(max-width:440px){.status-grid{grid-template-columns:1fr}.brand-line{flex-direction:column;gap:6px}.running-badge{align-self:flex-start}}@media(prefers-reduced-motion:reduce){.toast{transition:none}}</style>
<style>body{display:flex;justify-content:center}.shell{flex:0 1 1180px;min-width:0}.app-header{text-align:center}.brand-line{justify-content:center}main{text-align:left}@media(max-width:720px){.brand-line{align-items:center}}@media(max-width:440px){.running-badge{align-self:center}}</style>
</head><body><svg class="icon-sprite" aria-hidden="true"><symbol id="icon-copy" viewBox="0 0 24 24"><rect width="14" height="14" x="8" y="8" rx="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path></symbol><symbol id="icon-check" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"></path></symbol></svg>
<div class="shell"><header class="app-header"><div class="brand-line"><div class="brand">browser-debug / 浏览器运维</div><div class="running-badge"><span class="status-dot" aria-hidden="true"></span>CDP 已就绪</div></div><h1>Profile <span>$name</span></h1><p class="subtitle">独立 $browser 调试环境的连接参数与远程交接快照</p></header>
<section class="status-grid" aria-label="运行状态摘要"><div class="status-item"><span class="status-label">运行模式</span><span class="status-value">$modeLabel</span></div><div class="status-item"><span class="status-label">CDP 端口</span><span class="status-value">$cdpPort</span></div><div class="status-item"><span class="status-label">浏览器版本</span><span class="status-value">$cdpVersion</span></div><div class="status-item"><span class="status-label">快照时间</span><span class="status-value">$generatedAt</span></div></section>
<main><div class="content-grid"><section class="tool-panel quick-connect"><div class="panel-heading"><div><span class="section-kicker">快速连接</span><h2>本机 CDP</h2></div><span class="semantic-tag tag-connect">Ready</span></div>$(& $copyField 'CDP endpoint' ([string]$Snapshot.endpoint) 'connect')$(& $copyField '探测地址' ([string]$Snapshot.probeUrl))$(& $copyField 'Playwright attach' ([string]$Snapshot.playwrightCommand))</section>
<aside class="tool-panel metadata-panel"><div class="panel-heading"><div><span class="section-kicker">运行上下文</span><h2>Profile metadata</h2></div></div><dl class="metadata-grid"><div class="meta-row"><dt class="meta-label">Profile 路径</dt><dd class="meta-value">$profilePath</dd></div><div class="meta-row"><dt class="meta-label">浏览器</dt><dd class="meta-value">$browser</dd></div><div class="meta-row"><dt class="meta-label">监听地址</dt><dd class="meta-value">$listenAddress</dd></div><div class="meta-row"><dt class="meta-label">运行模式</dt><dd class="meta-value">$mode</dd></div><div class="meta-row"><dt class="meta-label">LAN IPv4</dt><dd class="meta-value">$lanAddresses</dd></div></dl></aside></div>
$warning<div class="scenario-stack">$lanSection$sshSection<section class="scenario-section agent-section"><div class="section-heading"><div><span class="section-kicker">Agent 交接</span><h2>Agent Prompts</h2></div></div><div class="connection-list">$($promptRows -join [Environment]::NewLine)</div></section></div></main></div>
<div id="copy-toast" class="toast" role="status" aria-live="polite" aria-atomic="true"></div>
<script>var copyFeedbackTimer;function fallbackCopy(value){var area=document.createElement('textarea');area.value=value;area.setAttribute('readonly','');area.style.position='fixed';area.style.opacity='0';document.body.appendChild(area);area.select();document.execCommand('copy');document.body.removeChild(area);}function showCopyFeedback(button,label){var icon=button.querySelector('use');var toast=document.getElementById('copy-toast');window.clearTimeout(copyFeedbackTimer);button.classList.add('is-copied');icon.setAttribute('href','#icon-check');toast.textContent='已复制：'+label;toast.classList.add('is-visible');copyFeedbackTimer=window.setTimeout(function(){button.classList.remove('is-copied');icon.setAttribute('href','#icon-copy');toast.classList.remove('is-visible');toast.textContent='';},1800);}document.querySelectorAll('[data-copy]').forEach(function(button){button.addEventListener('click',function(){var value=button.getAttribute('data-copy');var label=button.getAttribute('aria-label').replace(/^复制\s*/, '');var operation=navigator.clipboard&&window.isSecureContext?navigator.clipboard.writeText(value):Promise.reject();operation.catch(function(){fallbackCopy(value);}).then(function(){showCopyFeedback(button,label);});});});</script>
</body></html>
"@
}

<##
.SYNOPSIS
    原子写入模式专属帮助页。
.PARAMETER Snapshot
    启动帮助页快照。
.PARAMETER RegistryPath
    registry 路径，用于确定 guides 同级目录。
.OUTPUTS
    System.String
    返回生成的 HTML 绝对路径。
#>
function Write-BrowserDebugGuide {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Snapshot, [Parameter(Mandatory)][string]$RegistryPath)
    Assert-BrowserDebugName -Name ([string]$Snapshot.name) | Out-Null
    if ([string]$Snapshot.mode -notin 'local', 'lan') { throw "帮助页模式无效: $($Snapshot.mode)" }
    $guideDirectory = Join-Path (Split-Path -Parent $RegistryPath) 'guides'
    New-Item -ItemType Directory -Path $guideDirectory -Force | Out-Null
    $guidePath = Join-Path $guideDirectory "$($Snapshot.name)-$($Snapshot.mode).html"
    $temporaryPath = Join-Path $guideDirectory (".{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($guidePath)), [guid]::NewGuid().ToString('N'))
    try {
        ConvertTo-BrowserDebugGuideHtml -Snapshot $Snapshot | Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
        [System.IO.File]::Move($temporaryPath, $guidePath, $true)
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        throw
    }
    return $guidePath
}

<##
.SYNOPSIS
    使用目标浏览器和同一 User Data 打开静态帮助页。
.PARAMETER Profile
    Profile 注册对象。
.PARAMETER GuidePath
    已生成的 HTML 路径。
.OUTPUTS
    System.Diagnostics.Process
    返回浏览器启动器进程对象。
#>
function Open-BrowserDebugGuide {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Profile, [Parameter(Mandatory)][string]$GuidePath)
    $guideUri = [System.Uri]::new([System.IO.Path]::GetFullPath($GuidePath)).AbsoluteUri
    $process = Start-BrowserDebugDetachedProcess -FilePath ([string]$Profile.browserPath) -Arguments @("--user-data-dir=$($Profile.profilePath)", $guideUri)
    if ($null -eq $process) { throw '浏览器未返回可用的帮助页启动进程。' }
    return $process
}

<##
.SYNOPSIS
    构造 SSH 转发与 Agent 交接对象。
.PARAMETER Configuration
    SSH 配置对象。
.PARAMETER Profile
    关联 Profile 对象。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 SSH 参数、endpoint、Playwright 命令与中文 Prompt。
#>
function New-BrowserDebugSshInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Configuration, [Parameter(Mandatory)][object]$Profile)
    $forward = if ($Configuration.direction -eq 'local-forward') {
        "-L $($Configuration.agentPort):127.0.0.1:$($Profile.cdpPort)"
    }
    else { "-R $($Configuration.agentPort):127.0.0.1:$($Profile.cdpPort)" }
    $arguments = @('-4', '-N', '-o', 'ExitOnForwardFailure=yes')
    if ($Configuration.verboseLogging) { $arguments += '-vv' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Configuration.sshConfigPath)) { $arguments += @('-F', [string]$Configuration.sshConfigPath) }
    $arguments += @($forward.Split(' ', 2)[0], $forward.Split(' ', 2)[1], [string]$Configuration.target)
    $sshCommand = 'ssh ' + (($arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }) -join ' ')
    $endpoint = "http://127.0.0.1:$($Configuration.agentPort)"
    $attachCommand = "playwright-cli attach --cdp=$endpoint"
    $prompt = "请连接现有浏览器，不要创建新的浏览器实例。先确认 $endpoint/json/version 可访问，然后执行 ``$attachCommand``；失败时检查 SSH 隧道和 browser-debug profile status $($Profile.name)。"
    return [pscustomobject]@{
        name              = $Configuration.name
        direction         = $Configuration.direction
        profile           = $Profile.name
        cdpPort           = [int]$Profile.cdpPort
        agentPort         = [int]$Configuration.agentPort
        endpoint          = $endpoint
        sshArguments      = $arguments
        sshCommand        = $sshCommand
        playwrightCommand = $attachCommand
        probeUrl          = "$endpoint/json/version"
        agentPrompt       = $prompt
    }
}

<##
.SYNOPSIS
    获取 SSH 进程信息。
.PARAMETER ProcessId
    SSH 进程 PID。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 Win32_Process 对象，不存在时为空。
#>
function Get-BrowserDebugSshProcess {
    [CmdletBinding()]
    param([int]$ProcessId)
    if ($ProcessId -le 0 -or -not ($IsWindows -or $env:OS -eq 'Windows_NT')) { return $null }
    return Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId AND Name='ssh.exe'" -ErrorAction SilentlyContinue
}

<##
.SYNOPSIS
    验证 SSH 进程仍属于目标转发配置。
.PARAMETER Process
    Win32_Process 对象。
.PARAMETER Info
    SSH 交接对象。
.OUTPUTS
    System.Boolean
    返回完整转发参数和 target 是否匹配。
#>
function Test-BrowserDebugSshProcessOwnership {
    [CmdletBinding()]
    param([object]$Process, [Parameter(Mandatory)][object]$Info)
    if ($null -eq $Process) { return $false }
    $commandLine = [string]$Process.CommandLine
    foreach ($argument in @($Info.sshArguments)) {
        $escapedArgument = [regex]::Escape([string]$argument)
        if ($commandLine -notmatch "(?:^|\s)(?:`"$escapedArgument`"|$escapedArgument)(?=\s|$)") { return $false }
    }
    return $true
}

<##
.SYNOPSIS
    detached 启动 reverse-forward SSH。
.PARAMETER Info
    SSH 交接对象。
.OUTPUTS
    System.Int32
    返回 SSH PID。
#>
function Start-BrowserDebugSshProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Info)
    if ($Info.direction -ne 'reverse-forward') { throw 'local-forward 必须在远端 Agent 主机执行，Windows CLI 只生成命令。' }
    $sshPath = (Get-Command ssh.exe -ErrorAction Stop).Source
    $process = Start-BrowserDebugDetachedProcess -FilePath $sshPath -Arguments @($Info.sshArguments)
    if ($null -eq $process) { throw 'SSH 进程启动失败。' }
    Start-Sleep -Milliseconds 300
    if ($process.HasExited) { throw "SSH 启动后立即退出，退出码: $($process.ExitCode)" }
    return $process.Id
}
