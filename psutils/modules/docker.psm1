Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    检查 Docker Compose v2 是否可用。

.OUTPUTS
    bool。docker 命令存在且 `docker compose version` 成功时返回 true。
#>
function Test-DockerComposeAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }

    & docker 'compose' 'version' *> $null
    return $LASTEXITCODE -eq 0
}

<#
.SYNOPSIS
    校验 compose 模板、env 文件和 Docker Compose 前置条件。

.PARAMETER ComposeFile
    compose 模板路径。

.PARAMETER EnvFile
    可选 env 文件路径；缺失时只告警。

.PARAMETER EnvFileMissingMessage
    env 文件缺失时输出的告警文本。

.PARAMETER SkipDockerCheck
    为 true 时只校验文件，不检查 docker 命令。

.OUTPUTS
    None。校验失败时抛出异常。
#>
function Assert-DockerComposeReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,

        [AllowEmptyString()]
        [string]$EnvFile = '',

        [AllowEmptyString()]
        [string]$EnvFileMissingMessage = '',

        [switch]$SkipDockerCheck
    )

    if (-not (Test-Path -LiteralPath $ComposeFile)) {
        throw "未找到 compose 模板: $ComposeFile"
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvFile) -and -not (Test-Path -LiteralPath $EnvFile)) {
        $message = if ([string]::IsNullOrWhiteSpace($EnvFileMissingMessage)) {
            "未找到环境变量文件: $EnvFile。脚本会继续执行。"
        }
        else {
            $EnvFileMissingMessage
        }
        Write-Warning $message
    }

    if ($SkipDockerCheck) {
        return
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw '未找到 docker 命令，请先安装并确认 Docker Engine / Docker Desktop 已加入 PATH。'
    }

    & docker 'compose' 'version' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '未检测到可用的 docker compose 子命令，请确认本机 Docker 版本支持 compose v2。'
    }
}

<#
.SYNOPSIS
    生成 Docker Compose 基础参数。

.PARAMETER ComposeFile
    compose 模板路径。

.PARAMETER ProjectDirectory
    compose 项目目录。

.PARAMETER EnvFile
    可选 env 文件路径；存在时追加 `--env-file`。

.OUTPUTS
    string[]。不包含最前面 `docker` 的 compose 参数数组。
#>
function Get-DockerComposeBaseArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,

        [Parameter(Mandatory)]
        [string]$ProjectDirectory,

        [AllowEmptyString()]
        [string]$EnvFile = ''
    )

    $args = @(
        'compose'
        '-f'
        $ComposeFile
        '--project-directory'
        $ProjectDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($EnvFile) -and (Test-Path -LiteralPath $EnvFile)) {
        $args += @('--env-file', $EnvFile)
    }

    return [string[]]$args
}

<#
.SYNOPSIS
    执行或预览 Docker Compose 命令。

.PARAMETER ComposeArgs
    不包含最前面 `docker` 的完整 compose 参数。

.PARAMETER Environment
    临时注入到进程环境的变量。

.PARAMETER DryRun
    为 true 时只返回预览命令，不执行 docker。

.OUTPUTS
    string。DryRun 时返回预览命令；实际执行成功时返回空字符串。
#>
function Invoke-DockerComposeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComposeArgs,

        [hashtable]$Environment = @{},

        [switch]$DryRun
    )

    $environmentPrefix = ''
    if ($Environment.Count -gt 0) {
        $environmentPrefix = (($Environment.GetEnumerator() | Sort-Object Key | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ' ') + ' '
    }

    $preview = $environmentPrefix + 'docker ' + ($ComposeArgs -join ' ')
    if ($DryRun) {
        return $preview
    }

    $originalValues = @{}
    foreach ($entry in $Environment.GetEnumerator()) {
        $originalValues[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }

    try {
        & docker @ComposeArgs
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        foreach ($entry in $Environment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $originalValues[$entry.Key], 'Process')
        }
    }

    return ''
}

<#
.SYNOPSIS
    获取用于 WSL Docker wrapper 的候选发行版列表。

.PARAMETER PreferredDistro
    用户显式指定的首选 WSL 发行版名称。

.PARAMETER WslCommand
    用于执行 WSL 的命令名，默认值为 wsl.exe。

.OUTPUTS
    string[]。按优先级排序的候选 WSL 发行版名称。
#>
function Get-WslDockerCandidateDistro {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$PreferredDistro = '',

        [string]$WslCommand = 'wsl.exe'
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PreferredDistro)) {
        $candidates.Add($PreferredDistro.Trim()) | Out-Null
    }

    $envDistro = [Environment]::GetEnvironmentVariable('WSL_DOCKER_DISTRO', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envDistro)) {
        $candidates.Add($envDistro.Trim()) | Out-Null
    }

    try {
        $defaultOutput = & $WslCommand '--status' 2>$null
        if ($LASTEXITCODE -eq 0 -and $defaultOutput) {
            foreach ($line in @($defaultOutput)) {
                if ($line -match '^\s*Default Distribution:\s*(?<name>.+?)\s*$') {
                    $candidates.Add($Matches['name']) | Out-Null
                    break
                }
            }
        }
    }
    catch {
        Write-Verbose "读取 WSL 默认发行版失败: $($_.Exception.Message)"
    }

    try {
        $listOutput = & $WslCommand '--list' '--quiet' 2>$null
        if ($LASTEXITCODE -eq 0 -and $listOutput) {
            foreach ($line in @($listOutput)) {
                $name = ([string]$line).Trim(" `t`0")
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $candidates.Add($name) | Out-Null
                }
            }
        }
    }
    catch {
        Write-Verbose "读取 WSL 发行版列表失败: $($_.Exception.Message)"
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match '^docker-desktop') { continue }
        if ($seen.Add($candidate)) {
            $result.Add($candidate) | Out-Null
        }
    }

    return [string[]]$result.ToArray()
}

<#
.SYNOPSIS
    判断 Windows 侧 Docker Desktop / 原生 daemon 是否已经可用。

.PARAMETER DockerCommand
    Windows 侧 Docker 命令名，默认值为 docker。

.PARAMETER TimeoutSeconds
    预留超时时间，当前实现不强制终止外部命令。

.OUTPUTS
    bool。Windows 侧 `docker info` 成功且看起来不是 WSL wrapper 时返回 true。
#>
function Test-WindowsDockerDaemonAvailable {
    [CmdletBinding()]
    param(
        [string]$DockerCommand = 'docker',

        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 3
    )

    if (-not (Get-Command $DockerCommand -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $infoOutput = & $DockerCommand 'info' '--format' '{{json .}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $infoOutput) {
            return $false
        }

        $info = $infoOutput | ConvertFrom-Json -ErrorAction Stop
        $operatingSystem = if ($info.PSObject.Properties.Name -contains 'OperatingSystem') { [string]$info.OperatingSystem } else { '' }
        if ($operatingSystem -match 'Docker Desktop') {
            return $true
        }

        return $true
    }
    catch {
        Write-Verbose "Windows Docker daemon 探测失败: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    判断 Windows 侧当前 Docker daemon 是否来自 Docker Desktop。

.PARAMETER DockerCommand
    Windows 侧 Docker 命令名，默认值为 docker。

.OUTPUTS
    bool。`docker info` 成功且 OperatingSystem 含 Docker Desktop 时返回 true。
#>
function Test-DockerDesktopDaemonAvailable {
    [CmdletBinding()]
    param(
        [string]$DockerCommand = 'docker'
    )

    if (-not (Get-Command $DockerCommand -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $infoOutput = & $DockerCommand 'info' '--format' '{{json .}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $infoOutput) {
            return $false
        }

        $info = $infoOutput | ConvertFrom-Json -ErrorAction Stop
        $operatingSystem = if ($info.PSObject.Properties.Name -contains 'OperatingSystem') { [string]$info.OperatingSystem } else { '' }
        return $operatingSystem -match 'Docker Desktop'
    }
    catch {
        Write-Verbose "Docker Desktop daemon 探测失败: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    判断指定 WSL 发行版内是否存在可用的非 Docker Desktop Docker Engine。

.PARAMETER Distro
    要检查的 WSL 发行版名称。

.PARAMETER WslCommand
    用于执行 WSL 的命令名，默认值为 wsl.exe。

.OUTPUTS
    bool。发行版内 `docker info` 成功且 OperatingSystem 不含 Docker Desktop 时返回 true。
#>
function Test-WslDockerEngineAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Distro,

        [string]$WslCommand = 'wsl.exe'
    )

    if ([string]::IsNullOrWhiteSpace($Distro)) {
        return $false
    }

    try {
        $infoOutput = & $WslCommand '-d' $Distro '--' 'docker' 'info' '--format' '{{json .}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $infoOutput) {
            return $false
        }

        $info = $infoOutput | ConvertFrom-Json -ErrorAction Stop
        $operatingSystem = if ($info.PSObject.Properties.Name -contains 'OperatingSystem') { [string]$info.OperatingSystem } else { '' }
        if ($operatingSystem -match 'Docker Desktop') {
            return $false
        }

        return $true
    }
    catch {
        Write-Verbose "WSL Docker Engine 探测失败 [$Distro]: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    选择可用的 WSL Docker Engine 发行版。

.PARAMETER PreferredDistro
    用户显式指定的首选 WSL 发行版名称。

.PARAMETER WslCommand
    用于执行 WSL 的命令名，默认值为 wsl.exe。

.OUTPUTS
    string。返回第一个可用发行版名称；找不到时返回空字符串。
#>
function Resolve-WslDockerDistro {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$PreferredDistro = '',

        [string]$WslCommand = 'wsl.exe'
    )

    $wsl = Get-Command $WslCommand -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return ''
    }

    foreach ($distro in (Get-WslDockerCandidateDistro -PreferredDistro $PreferredDistro -WslCommand $WslCommand)) {
        if (Test-WslDockerEngineAvailable -Distro $distro -WslCommand $WslCommand) {
            return $distro
        }
    }

    return ''
}

<#
.SYNOPSIS
    把 Windows 路径转换为 WSL 路径。

.PARAMETER Path
    待转换的 Windows 或普通路径。

.PARAMETER WslCommand
    用于调用 `wslpath` 的 WSL 命令名，默认值为 wsl.exe。

.PARAMETER Distro
    可选 WSL 发行版名称；传入时在指定发行版中执行 `wslpath`。

.OUTPUTS
    string。可转换时返回 WSL 路径，否则返回原始路径。
#>
function ConvertTo-WslDockerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [string]$WslCommand = 'wsl.exe',

        [AllowEmptyString()]
        [string]$Distro = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $pathToConvert = $Path
    if (-not ($pathToConvert -match '^[A-Za-z]:[\\/]' -or $pathToConvert -match '^\\\\')) {
        if ($pathToConvert -notmatch '^/' -and (Test-Path -LiteralPath $pathToConvert)) {
            $pathToConvert = (Resolve-Path -LiteralPath $pathToConvert).Path
        }
        else {
            return $Path
        }
    }

    try {
        $args = @()
        if (-not [string]::IsNullOrWhiteSpace($Distro)) {
            $args += @('-d', $Distro)
        }
        $args += @('--', 'wslpath', '-a', $pathToConvert)
        $converted = & $WslCommand @args 2>$null
        if ($LASTEXITCODE -eq 0 -and $converted) {
            return ([string](@($converted)[0])).Trim()
        }
    }
    catch {
        Write-Verbose "wslpath 转换失败 [$Path]: $($_.Exception.Message)"
    }

    return $Path
}

<#
.SYNOPSIS
    转换 Docker `-v` / `--volume` 参数中的宿主机路径。

.PARAMETER VolumeSpec
    Docker volume 参数值，例如 `C:\data:/data:ro`。

.PARAMETER WslCommand
    用于调用 `wslpath` 的 WSL 命令名，默认值为 wsl.exe。

.PARAMETER Distro
    可选 WSL 发行版名称。

.OUTPUTS
    string。宿主机路径已转换的 volume 参数值。
#>
function ConvertTo-WslDockerVolumeSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeSpec,

        [string]$WslCommand = 'wsl.exe',

        [AllowEmptyString()]
        [string]$Distro = ''
    )

    if ([string]::IsNullOrWhiteSpace($VolumeSpec)) {
        return $VolumeSpec
    }

    if ($VolumeSpec -match '^(?<source>(?:[A-Za-z]:[\\/]|\.{1,2}[\\/])[^:]*)(?<rest>:.+)$') {
        $source = $Matches['source']
        $rest = $Matches['rest']
        return (ConvertTo-WslDockerPath -Path $source -WslCommand $WslCommand -Distro $Distro) + $rest
    }

    return $VolumeSpec
}

<#
.SYNOPSIS
    转换 Docker `--mount type=bind` 参数中的 source/src 字段。

.PARAMETER MountSpec
    Docker mount 参数值，例如 `type=bind,src=C:\data,target=/data`。

.PARAMETER WslCommand
    用于调用 `wslpath` 的 WSL 命令名，默认值为 wsl.exe。

.PARAMETER Distro
    可选 WSL 发行版名称。

.OUTPUTS
    string。source/src 字段已转换的 mount 参数值。
#>
function ConvertTo-WslDockerMountSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MountSpec,

        [string]$WslCommand = 'wsl.exe',

        [AllowEmptyString()]
        [string]$Distro = ''
    )

    if ([string]::IsNullOrWhiteSpace($MountSpec)) {
        return $MountSpec
    }

    $parts = $MountSpec -split ','
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i] -match '^(?<key>src|source)=(?<value>.+)$') {
            $parts[$i] = '{0}={1}' -f $Matches['key'], (ConvertTo-WslDockerPath -Path $Matches['value'] -WslCommand $WslCommand -Distro $Distro)
        }
    }

    return ($parts -join ',')
}

<#
.SYNOPSIS
    生成需要透传到 WSL Docker 进程的环境变量参数。

.PARAMETER Distro
    目标 WSL 发行版名称。

.PARAMETER WslCommand
    用于调用 `wslpath` 的 WSL 命令名，默认值为 wsl.exe。

.OUTPUTS
    string[]。可直接传给 `env` 命令的 `KEY=value` 参数。
#>
function Get-WslDockerEnvironmentArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Distro,

        [string]$WslCommand = 'wsl.exe'
    )

    $forwardNamesRaw = [Environment]::GetEnvironmentVariable('WSL_DOCKER_FORWARD_ENV', 'Process')
    $pathNamesRaw = [Environment]::GetEnvironmentVariable('WSL_DOCKER_PATH_ENV', 'Process')
    $forwardNames = if ([string]::IsNullOrWhiteSpace($forwardNamesRaw)) {
        @('DATA_PATH', 'COMPOSE_PROJECT_NAME', 'COMPOSE_PROFILES', 'DOCKER_BUILDKIT', 'BUILDKIT_PROGRESS')
    }
    else {
        $forwardNamesRaw -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    $pathNames = if ([string]::IsNullOrWhiteSpace($pathNamesRaw)) {
        @('DATA_PATH')
    }
    else {
        $pathNamesRaw -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    $pathNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($pathNames)) {
        $pathNameSet.Add($name) | Out-Null
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($forwardNames)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($null -eq $value) { continue }
        if ($pathNameSet.Contains($name)) {
            $value = ConvertTo-WslDockerPath -Path $value -WslCommand $WslCommand -Distro $Distro
        }
        $result.Add(('{0}={1}' -f $name, $value)) | Out-Null
    }

    return [string[]]$result.ToArray()
}

<#
.SYNOPSIS
    转换 docker / docker compose 参数中的常见路径参数。

.PARAMETER Arguments
    传给 docker 的原始参数。

.PARAMETER Distro
    目标 WSL 发行版名称。

.PARAMETER WslCommand
    用于调用 WSL 的命令名，默认值为 wsl.exe。

.OUTPUTS
    string[]。转换后的 docker 参数数组。
#>
function ConvertTo-WslDockerArgument {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Distro,

        [string]$WslCommand = 'wsl.exe'
    )

    $pathValueOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @('-f', '--file', '--env-file', '--project-directory')) {
        $pathValueOptions.Add($option) | Out-Null
    }
    $volumeValueOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @('-v', '--volume')) {
        $volumeValueOptions.Add($option) | Out-Null
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $convertNext = $false
    $convertNextVolume = $false

    foreach ($argument in @($Arguments)) {
        $value = [string]$argument

        if ($convertNext) {
            $result.Add((ConvertTo-WslDockerPath -Path $value -WslCommand $WslCommand -Distro $Distro)) | Out-Null
            $convertNext = $false
            continue
        }

        if ($convertNextVolume) {
            $result.Add((ConvertTo-WslDockerVolumeSpec -VolumeSpec $value -WslCommand $WslCommand -Distro $Distro)) | Out-Null
            $convertNextVolume = $false
            continue
        }

        $matchedEqualsOption = $false
        foreach ($option in $pathValueOptions) {
            $prefix = "$option="
            if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $pathPart = $value.Substring($prefix.Length)
                $result.Add($prefix + (ConvertTo-WslDockerPath -Path $pathPart -WslCommand $WslCommand -Distro $Distro)) | Out-Null
                $matchedEqualsOption = $true
                break
            }
        }
        if ($matchedEqualsOption) { continue }

        if ($pathValueOptions.Contains($value)) {
            $result.Add($value) | Out-Null
            $convertNext = $true
            continue
        }

        foreach ($option in $volumeValueOptions) {
            $prefix = "$option="
            if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $volumePart = $value.Substring($prefix.Length)
                $result.Add($prefix + (ConvertTo-WslDockerVolumeSpec -VolumeSpec $volumePart -WslCommand $WslCommand -Distro $Distro)) | Out-Null
                $matchedEqualsOption = $true
                break
            }
        }
        if ($matchedEqualsOption) { continue }

        if ($volumeValueOptions.Contains($value)) {
            $result.Add($value) | Out-Null
            $convertNextVolume = $true
            continue
        }

        if ($value.StartsWith('--mount=', [System.StringComparison]::OrdinalIgnoreCase)) {
            $mountSpec = $value.Substring('--mount='.Length)
            $result.Add('--mount=' + (ConvertTo-WslDockerMountSpec -MountSpec $mountSpec -WslCommand $WslCommand -Distro $Distro)) | Out-Null
            continue
        }

        if ($value.StartsWith('type=bind,', [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Add((ConvertTo-WslDockerMountSpec -MountSpec $value -WslCommand $WslCommand -Distro $Distro)) | Out-Null
            continue
        }

        # 普通位置参数可能是 compose 服务名、镜像名或容器名，只有绝对 Windows 路径才自动转换。
        if ($value -match '^[A-Za-z]:[\\/]' -or $value -match '^\\\\') {
            $result.Add((ConvertTo-WslDockerPath -Path $value -WslCommand $WslCommand -Distro $Distro)) | Out-Null
        }
        else {
            $result.Add($value) | Out-Null
        }
    }

    return [string[]]$result.ToArray()
}

<#
.SYNOPSIS
    调用 WSL 内 Docker CLI，并保留原生退出码。

.PARAMETER Distro
    目标 WSL 发行版名称。

.PARAMETER Arguments
    传给 docker 的参数。

.PARAMETER WslCommand
    用于执行 WSL 的命令名，默认值为 wsl.exe。

.OUTPUTS
    None。直接透传 WSL Docker 的 stdout/stderr；失败时设置 `$global:LASTEXITCODE`。
#>
function Invoke-WslDocker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Distro,

        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Arguments,

        [string]$WslCommand = 'wsl.exe'
    )

    $convertedArgs = ConvertTo-WslDockerArgument -Arguments $Arguments -Distro $Distro -WslCommand $WslCommand
    $workingDirectory = ConvertTo-WslDockerPath -Path (Get-Location).Path -WslCommand $WslCommand -Distro $Distro
    if ([string]::IsNullOrWhiteSpace($workingDirectory) -or $workingDirectory -match '^[A-Za-z]:[\\/]') {
        $workingDirectory = '~'
    }

    $envArgs = @(Get-WslDockerEnvironmentArgument -Distro $Distro -WslCommand $WslCommand)
    if ($envArgs.Count -gt 0) {
        & $WslCommand '-d' $Distro '--cd' $workingDirectory '--' 'env' @envArgs 'docker' @convertedArgs
    }
    else {
        & $WslCommand '-d' $Distro '--cd' $workingDirectory '--' 'docker' @convertedArgs
    }
    $global:LASTEXITCODE = $LASTEXITCODE
}

<#
.SYNOPSIS
    在当前 PowerShell 会话中启用 Docker 到 WSL Docker Engine 的 wrapper。

.PARAMETER Distro
    可选目标 WSL 发行版；为空时自动选择默认发行版或第一个可用发行版。

.PARAMETER Force
    即使 Windows 侧 Docker daemon 可用，也强制注册 wrapper。

.PARAMETER WslCommand
    用于执行 WSL 的命令名，默认值为 wsl.exe。

.PARAMETER DockerCommand
    Windows 侧 Docker 命令名，默认值为 docker。

.OUTPUTS
    bool。成功注册 wrapper 时返回 true，否则返回 false。
#>
function Enable-WslDockerWrapper {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Distro = '',

        [switch]$Force,

        [string]$WslCommand = 'wsl.exe',

        [string]$DockerCommand = 'docker'
    )

    if (-not $Force -and (Test-DockerDesktopDaemonAvailable -DockerCommand $DockerCommand)) {
        Write-Verbose 'Docker Desktop daemon 已可用，跳过 WSL Docker wrapper。'
        return $false
    }

    $resolvedDistro = Resolve-WslDockerDistro -PreferredDistro $Distro -WslCommand $WslCommand
    if ([string]::IsNullOrWhiteSpace($resolvedDistro)) {
        Write-Verbose '未检测到可用的 WSL Docker Engine，跳过 WSL Docker wrapper。'
        return $false
    }

    $__wslDockerDistro = $resolvedDistro
    $__wslCommand = $WslCommand

    $wrapper = {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$DockerArgs
        )
        Invoke-WslDocker -Distro $__wslDockerDistro -Arguments $DockerArgs -WslCommand $__wslCommand
    }.GetNewClosure()

    New-Item -Path "Function:Global:$DockerCommand" -Value $wrapper -Force | Out-Null
    [Environment]::SetEnvironmentVariable('WSL_DOCKER_WRAPPER_ACTIVE', '1', 'Process')
    [Environment]::SetEnvironmentVariable('WSL_DOCKER_WRAPPER_DISTRO', $resolvedDistro, 'Process')
    Write-Verbose "已启用 WSL Docker wrapper: $DockerCommand -> $resolvedDistro"
    return $true
}

Export-ModuleMember -Function @(
    'Test-DockerComposeAvailable'
    'Assert-DockerComposeReady'
    'Get-DockerComposeBaseArgs'
    'Invoke-DockerComposeCommand'
    'Get-WslDockerCandidateDistro'
    'Test-WindowsDockerDaemonAvailable'
    'Test-DockerDesktopDaemonAvailable'
    'Test-WslDockerEngineAvailable'
    'Resolve-WslDockerDistro'
    'ConvertTo-WslDockerPath'
    'ConvertTo-WslDockerVolumeSpec'
    'ConvertTo-WslDockerMountSpec'
    'Get-WslDockerEnvironmentArgument'
    'ConvertTo-WslDockerArgument'
    'Invoke-WslDocker'
    'Enable-WslDockerWrapper'
)
