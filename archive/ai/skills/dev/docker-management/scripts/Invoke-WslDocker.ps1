#requires -Version 5.1
<#
.SYNOPSIS
    从 Windows PowerShell 调用 WSL 发行版内的 Docker CLI。

.DESCRIPTION
    该脚本用于方案 D：保留 Windows PowerShell 入口，但把 docker 命令转发到 WSL 内执行。
    脚本会在启用前确认目标 WSL 发行版内存在非 Docker Desktop 的 Docker Engine，并把常见
    compose 文件路径、env file、project directory、bind mount 源路径和 DATA_PATH 转换为 WSL 路径。

.PARAMETER Distro
    目标 WSL 发行版名称。未指定时优先使用 WSL_DOCKER_DISTRO，其次使用 WSL 默认发行版。

.PARAMETER DockerArgs
    传给 WSL 内 docker 命令的剩余参数。

.PARAMETER SkipEngineCheck
    跳过 WSL 内 `docker info` 检查。仅用于排障或已由外部流程完成检测的场景。

.OUTPUTS
    None。直接透传 docker stdout/stderr，并以 docker 的退出码结束。

.EXAMPLE
    .\Invoke-WslDocker.ps1 version

.EXAMPLE
    .\Invoke-WslDocker.ps1 compose -f .\docker-compose.yml config
#>
[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Distro = '',

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$DockerArgs,

    [switch]$SkipEngineCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    获取 WSL 默认发行版。

.OUTPUTS
    string。找到默认发行版时返回名称，否则返回空字符串。
#>
function Get-DefaultWslDockerDistro {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($Distro)) {
        return $Distro
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WSL_DOCKER_DISTRO)) {
        return $env:WSL_DOCKER_DISTRO
    }

    $status = & wsl.exe --status 2>$null
    if ($LASTEXITCODE -eq 0 -and $status) {
        foreach ($line in @($status)) {
            if ($line -match '^\s*Default Distribution:\s*(?<name>.+?)\s*$') {
                return $Matches['name']
            }
        }
    }

    return ''
}

<#
.SYNOPSIS
    判断指定 WSL 发行版内 Docker Engine 是否可用且不是 Docker Desktop。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    bool。`docker info` 成功且 OperatingSystem 不含 Docker Desktop 时返回 true。
#>
function Test-WslDockerEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    $infoOutput = & wsl.exe -d $Name -- docker info --format '{{json .}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $infoOutput) {
        return $false
    }

    try {
        $info = $infoOutput | ConvertFrom-Json -ErrorAction Stop
        $operatingSystem = if ($info.PSObject.Properties.Name -contains 'OperatingSystem') { [string]$info.OperatingSystem } else { '' }
        return -not ($operatingSystem -match 'Docker Desktop')
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    将 Windows 路径转换为 WSL 路径。

.PARAMETER Path
    需要转换的路径。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    string。可转换时返回 WSL 路径，否则返回原值。
#>
function ConvertTo-WslPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
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

    $converted = & wsl.exe -d $Name -- wslpath -a $pathToConvert 2>$null
    if ($LASTEXITCODE -eq 0 -and $converted) {
        return ([string](@($converted)[0])).Trim()
    }

    return $Path
}

<#
.SYNOPSIS
    转换 Docker `-v` / `--volume` 参数中的宿主机路径。

.PARAMETER VolumeSpec
    Docker volume 参数值。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    string。转换后的 volume 参数。
#>
function ConvertTo-WslVolumeSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeSpec,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($VolumeSpec -match '^(?<source>(?:[A-Za-z]:[\\/]|\.{1,2}[\\/])[^:]*)(?<rest>:.+)$') {
        return (ConvertTo-WslPath -Path $Matches['source'] -Name $Name) + $Matches['rest']
    }

    return $VolumeSpec
}

<#
.SYNOPSIS
    转换 Docker `--mount type=bind` 参数中的 source/src 字段。

.PARAMETER MountSpec
    Docker mount 参数值。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    string。转换后的 mount 参数。
#>
function ConvertTo-WslMountSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MountSpec,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $parts = $MountSpec -split ','
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i] -match '^(?<key>src|source)=(?<value>.+)$') {
            $parts[$i] = '{0}={1}' -f $Matches['key'], (ConvertTo-WslPath -Path $Matches['value'] -Name $Name)
        }
    }

    return ($parts -join ',')
}

<#
.SYNOPSIS
    转换传给 docker 的常见路径参数。

.PARAMETER Arguments
    原始 docker 参数。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    string[]。转换后的 docker 参数。
#>
function ConvertTo-WslDockerArguments {
    [CmdletBinding()]
    param(
        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $pathOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @('-f', '--file', '--env-file', '--project-directory')) {
        $pathOptions.Add($option) | Out-Null
    }
    $volumeOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @('-v', '--volume')) {
        $volumeOptions.Add($option) | Out-Null
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $convertNextPath = $false
    $convertNextVolume = $false

    foreach ($arg in @($Arguments)) {
        $value = [string]$arg

        if ($convertNextPath) {
            $result.Add((ConvertTo-WslPath -Path $value -Name $Name)) | Out-Null
            $convertNextPath = $false
            continue
        }

        if ($convertNextVolume) {
            $result.Add((ConvertTo-WslVolumeSpec -VolumeSpec $value -Name $Name)) | Out-Null
            $convertNextVolume = $false
            continue
        }

        if ($pathOptions.Contains($value)) {
            $result.Add($value) | Out-Null
            $convertNextPath = $true
            continue
        }

        if ($volumeOptions.Contains($value)) {
            $result.Add($value) | Out-Null
            $convertNextVolume = $true
            continue
        }

        $handled = $false
        foreach ($option in $pathOptions) {
            $prefix = "$option="
            if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.Add($prefix + (ConvertTo-WslPath -Path $value.Substring($prefix.Length) -Name $Name)) | Out-Null
                $handled = $true
                break
            }
        }
        if ($handled) { continue }

        foreach ($option in $volumeOptions) {
            $prefix = "$option="
            if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.Add($prefix + (ConvertTo-WslVolumeSpec -VolumeSpec $value.Substring($prefix.Length) -Name $Name)) | Out-Null
                $handled = $true
                break
            }
        }
        if ($handled) { continue }

        if ($value.StartsWith('--mount=', [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Add('--mount=' + (ConvertTo-WslMountSpec -MountSpec $value.Substring('--mount='.Length) -Name $Name)) | Out-Null
            continue
        }

        if ($value.StartsWith('type=bind,', [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Add((ConvertTo-WslMountSpec -MountSpec $value -Name $Name)) | Out-Null
            continue
        }

        # 普通位置参数可能是 compose 服务名、镜像名或容器名，只有绝对 Windows 路径才自动转换。
        if ($value -match '^[A-Za-z]:[\\/]' -or $value -match '^\\\\') {
            $result.Add((ConvertTo-WslPath -Path $value -Name $Name)) | Out-Null
        }
        else {
            $result.Add($value) | Out-Null
        }
    }

    return [string[]]$result.ToArray()
}

<#
.SYNOPSIS
    生成需要传入 WSL Docker 进程的环境变量参数。

.PARAMETER Name
    WSL 发行版名称。

.OUTPUTS
    string[]。`KEY=value` 格式的 env 参数。
#>
function Get-WslDockerEnvArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $forwardNames = @('DATA_PATH', 'COMPOSE_PROJECT_NAME', 'COMPOSE_PROFILES', 'DOCKER_BUILDKIT', 'BUILDKIT_PROGRESS')
    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($envName in $forwardNames) {
        $value = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if ($null -eq $value) { continue }
        if ($envName -eq 'DATA_PATH') {
            $value = ConvertTo-WslPath -Path $value -Name $Name
        }
        $result.Add(('{0}={1}' -f $envName, $value)) | Out-Null
    }

    return [string[]]$result.ToArray()
}

$targetDistro = Get-DefaultWslDockerDistro
if ([string]::IsNullOrWhiteSpace($targetDistro)) {
    Write-Error '未检测到 WSL 默认发行版。请先安装 WSL，或通过 -Distro / WSL_DOCKER_DISTRO 指定发行版。'
    exit 127
}

if (-not $SkipEngineCheck -and -not (Test-WslDockerEngine -Name $targetDistro)) {
    Write-Error "WSL 发行版 [$targetDistro] 内未检测到可用的非 Docker Desktop Docker Engine。"
    exit 127
}

$convertedArgs = ConvertTo-WslDockerArguments -Arguments $DockerArgs -Name $targetDistro
$workingDirectory = ConvertTo-WslPath -Path (Get-Location).Path -Name $targetDistro
if ([string]::IsNullOrWhiteSpace($workingDirectory) -or $workingDirectory -match '^[A-Za-z]:[\\/]') {
    $workingDirectory = '~'
}

$envArgs = @(Get-WslDockerEnvArgs -Name $targetDistro)
if ($envArgs.Count -gt 0) {
    & wsl.exe -d $targetDistro --cd $workingDirectory -- env @envArgs docker @convertedArgs
}
else {
    & wsl.exe -d $targetDistro --cd $workingDirectory -- docker @convertedArgs
}
exit $LASTEXITCODE
