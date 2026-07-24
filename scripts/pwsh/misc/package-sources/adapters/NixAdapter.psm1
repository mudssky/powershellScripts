Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AdapterSupport.psm1') -Force

# 官方 cache 签名公钥（与 Nix 默认一致；镜像站代理同一信任根）
$script:NixOfficialTrustedPublicKey = 'cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY='
$script:NixOfficialCache = 'https://cache.nixos.org/'

function Resolve-NixPackageSourceResourcePath {
    <#
    .SYNOPSIS
        将 catalog 中的 /etc/nix/nix.conf 映射到真实系统路径或测试系统根。

    .PARAMETER Path
        catalog 中的绝对 Unix 路径，通常为 /etc/nix/nix.conf。

    .OUTPUTS
        string。实际读写的配置文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $testRoot = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', 'Process')
    if ([string]::IsNullOrWhiteSpace($testRoot)) {
        return $Path
    }
    return Join-Path $testRoot $Path.TrimStart('/', '\')
}

function Get-NixPackageSourcePath {
    <#
    .SYNOPSIS
        返回当前环境的 nix.conf 路径。

    .PARAMETER TargetConfig
        catalog 中 nix target 的配置；使用 resource 字段。

    .OUTPUTS
        string。nix.conf 路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    $resource = [string]$TargetConfig.resource
    if ([string]::IsNullOrWhiteSpace($resource)) {
        $resource = '/etc/nix/nix.conf'
    }
    return Resolve-NixPackageSourceResourcePath -Path $resource
}

function Get-NixPackageSourceResourcePath {
    <#
    .SYNOPSIS
        返回 Apply 前需要 snapshot 的文件列表。

    .PARAMETER TargetConfig
        catalog 中 nix target 的配置。

    .OUTPUTS
        string[]。资源路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    return @(Get-NixPackageSourcePath -TargetConfig $TargetConfig)
}

function Assert-NixPackageSourcePrivilege {
    <#
    .SYNOPSIS
        真实系统路径写入前要求 root；测试系统根跳过。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    $testRoot = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($testRoot)) {
        return
    }
    if (-not $IsLinux -and -not $IsMacOS) {
        throw (New-PackageSourceAdapterException -Message 'Nix source adapter 仅支持 Linux/macOS' -ExitCode 10 -Code 'Blocked')
    }
    if ($IsLinux) {
        $id = Invoke-PackageSourceProcess -FilePath 'id' -ArgumentList @('-u')
        if ($id.ExitCode -ne 0 -or [string]$id.StdOut.Trim() -ne '0') {
            throw (New-PackageSourceAdapterException -Message '修改 /etc/nix/nix.conf 需要 root 权限（sudo）' -ExitCode 10 -Code 'Blocked')
        }
    }
}

function Get-NixPackageSourceState {
    <#
    .SYNOPSIS
        读取当前 nix.conf 中的首个 substituter 作为 Source。

    .PARAMETER TargetConfig
        catalog 中 nix target 的配置。

    .OUTPUTS
        PSCustomObject 或 $null。包含 Source。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    $path = Get-NixPackageSourcePath -TargetConfig $TargetConfig
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    $settings = ConvertFrom-NixConfText -Text $text
    $subs = @($settings['substituters'] -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($subs.Count -eq 0) {
        return $null
    }
    return [PSCustomObject]@{
        Source = ConvertTo-SafePackageSourceUrl -Value $subs[0]
    }
}

function ConvertFrom-NixConfText {
    <#
    .SYNOPSIS
        解析 nix.conf 文本为键值表，保留未知键。

    .PARAMETER Text
        nix.conf 全文。

    .OUTPUTS
        hashtable。键为设置名，值为去掉注释后的值字符串。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    $map = [ordered]@{}
    if ([string]::IsNullOrEmpty($Text)) {
        return $map
    }
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) {
            continue
        }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        # 行内注释
        $hashIdx = $value.IndexOf('#')
        if ($hashIdx -ge 0) {
            $value = $value.Substring(0, $hashIdx).Trim()
        }
        $map[$key] = $value
    }
    return $map
}

function Merge-NixConfSubstituters {
    <#
    .SYNOPSIS
        合并 nix.conf：只改 substituters 与 trusted-public-keys，保留其它行。

    .PARAMETER ExistingText
        现有配置全文；可为 null。

    .PARAMETER MirrorUrls
        镜像 URL 列表，官方 fallback 会自动追加到末尾。

    .PARAMETER TrustedPublicKeys
        需要确保存在的公钥列表。

    .OUTPUTS
        string。合并后的完整配置文本。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ExistingText,

        [Parameter(Mandatory)]
        [string[]]$MirrorUrls,

        [Parameter(Mandatory)]
        [string[]]$TrustedPublicKeys
    )

    $settings = ConvertFrom-NixConfText -Text $(if ($null -eq $ExistingText) { '' } else { $ExistingText })

    # 禁止关闭签名
    if ($settings.Contains('require-sigs') -and $settings['require-sigs'] -match 'false') {
        throw (New-PackageSourceAdapterException -Message '拒绝应用：现有 nix.conf 含 require-sigs = false' -ExitCode 10 -Code 'Blocked')
    }

    $official = $script:NixOfficialCache.TrimEnd('/') + '/'
    $ordered = [System.Collections.Generic.List[string]]::new()
    foreach ($url in $MirrorUrls) {
        $safe = (ConvertTo-SafePackageSourceUrl -Value $url).TrimEnd('/') + '/'
        if ($safe -ieq $official) { continue }
        if (-not $ordered.Contains($safe)) { $ordered.Add($safe) }
    }
    # 官方 fallback 必须保留在末尾
    if (-not $ordered.Contains($official)) {
        $ordered.Add($official)
    }
    else {
        $null = $ordered.Remove($official)
        $ordered.Add($official)
    }
    $settings['substituters'] = ($ordered -join ' ')

    $keys = [System.Collections.Generic.List[string]]::new()
    $existingKeys = @()
    if ($settings.Contains('trusted-public-keys') -and -not [string]::IsNullOrWhiteSpace([string]$settings['trusted-public-keys'])) {
        $existingKeys = @([string]$settings['trusted-public-keys'] -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    foreach ($k in $existingKeys) {
        if (-not $keys.Contains($k)) { $keys.Add($k) }
    }
    foreach ($k in $TrustedPublicKeys) {
        if (-not $keys.Contains($k)) { $keys.Add($k) }
    }
    if (-not $keys.Contains($script:NixOfficialTrustedPublicKey)) {
        $keys.Add($script:NixOfficialTrustedPublicKey)
    }
    $settings['trusted-public-keys'] = ($keys -join ' ')

    # 重建：保留原文件非 managed 行顺序，再覆盖 managed 键
    $managed = @('substituters', 'trusted-public-keys')
    $lines = [System.Collections.Generic.List[string]]::new()
    $seenManaged = @{}
    if (-not [string]::IsNullOrEmpty($ExistingText)) {
        foreach ($rawLine in ($ExistingText -split "`r?`n", [System.StringSplitOptions]::None)) {
            $trim = $rawLine.Trim()
            if ($trim.StartsWith('#') -or [string]::IsNullOrWhiteSpace($trim)) {
                $lines.Add($rawLine)
                continue
            }
            $eq = $trim.IndexOf('=')
            if ($eq -lt 1) {
                $lines.Add($rawLine)
                continue
            }
            $key = $trim.Substring(0, $eq).Trim()
            if ($managed -contains $key) {
                if (-not $seenManaged.ContainsKey($key)) {
                    $lines.Add("$key = $($settings[$key])")
                    $seenManaged[$key] = $true
                }
                continue
            }
            $lines.Add($rawLine)
        }
    }
    foreach ($key in $managed) {
        if (-not $seenManaged.ContainsKey($key)) {
            $lines.Add("$key = $($settings[$key])")
        }
    }
    # 去掉末尾多余空行再补一个换行
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }
    return (($lines -join "`n") + "`n")
}

function Test-NixPackageSourceUrl {
    <#
    .SYNOPSIS
        探测 Nix binary cache 的 nix-cache-info 端点。

    .PARAMETER Url
        cache 根 URL。

    .PARAMETER TimeoutSeconds
        超时秒数。

    .PARAMETER Retry
        重试次数。

    .OUTPUTS
        PSCustomObject。Url/Success/StatusCode/ElapsedMs/Error。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 5,

        [ValidateRange(0, 5)]
        [int]$Retry = 1
    )

    $safeUrl = ConvertTo-SafePackageSourceUrl -Value $Url
    $probeUrl = $safeUrl.TrimEnd('/') + '/nix-cache-info'
    $lastError = ''
    for ($attempt = 0; $attempt -le $Retry; $attempt++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest -Uri $probeUrl -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            $sw.Stop()
            $code = [int]$response.StatusCode
            $content = if ($response.Content -is [byte[]]) {
                [System.Text.Encoding]::UTF8.GetString($response.Content)
            }
            else {
                [string]$response.Content
            }
            if ($code -eq 200 -and $content -match 'StoreDir:') {
                return [PSCustomObject]@{
                    Url        = $safeUrl.TrimEnd('/')
                    Success    = $true
                    StatusCode = $code
                    ElapsedMs  = [int]$sw.ElapsedMilliseconds
                    Error      = ''
                }
            }
            $lastError = "unexpected response status=$code"
        }
        catch {
            $lastError = $_.Exception.Message
        }
        $sw.Stop()
    }
    return [PSCustomObject]@{
        Url        = $safeUrl.TrimEnd('/')
        Success    = $false
        StatusCode = 0
        ElapsedMs  = 0
        Error      = $lastError
    }
}

function Invoke-NixPackageSourceRestart {
    <#
    .SYNOPSIS
        重启 nix-daemon（Linux systemd / macOS launchctl）。

    .OUTPUTS
        string。重启结果描述。
    #>
    [CmdletBinding()]
    param()

    if ([Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_NIX_RESTART', 'Process') -eq '1') {
        return '测试环境已跳过 nix-daemon 重启'
    }
    if ([Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_NIX_RESTART_FAIL', 'Process') -eq '1') {
        throw (New-PackageSourceAdapterException -Message '模拟 nix-daemon 重启失败' -ExitCode 10 -Code 'Blocked')
    }

    if ($IsLinux) {
        $systemctl = Get-Command systemctl -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $systemctl) {
            $restart = Invoke-PackageSourceProcess -FilePath $systemctl.Source -ArgumentList @('restart', 'nix-daemon')
            if ($restart.ExitCode -eq 0) {
                return 'nix-daemon 已通过 systemctl 重启'
            }
            throw (New-PackageSourceAdapterException -Message "nix-daemon systemctl 重启失败: $($restart.StdErr)" -ExitCode 10 -Code 'Blocked')
        }
    }

    if ($IsMacOS) {
        $launchctl = Get-Command launchctl -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $launchctl) {
            $null = Invoke-PackageSourceProcess -FilePath $launchctl.Source -ArgumentList @('kickstart', '-k', 'system/org.nixos.nix-daemon')
            return '已请求 launchctl kickstart org.nixos.nix-daemon'
        }
    }

    throw (New-PackageSourceAdapterException -Message '无法定位 nix-daemon 重启方式' -ExitCode 10 -Code 'Blocked')
}

function Invoke-NixPackageSourceApply {
    <#
    .SYNOPSIS
        将 USTC 等镜像写入 nix.conf 的 substituters，并保留官方 cache 与签名密钥。

    .PARAMETER TargetConfig
        catalog 中 nix target 配置。

    .PARAMETER MirrorUrl
        可选镜像覆盖列表。

    .PARAMETER TimeoutSeconds
        探活超时。

    .PARAMETER Retry
        探活重试。

    .OUTPUTS
        PSCustomObject。Source/Changed/ChsrcVersion/Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [string[]]$MirrorUrl = @(),

        [int]$TimeoutSeconds = 5,

        [int]$Retry = 1
    )

    Assert-NixPackageSourcePrivilege

    # 强制数组：PowerShell 会把单元素 @(...) 解包成标量，导致 .Count 失败
    $candidates = @(
        if (@($MirrorUrl).Count -gt 0) {
            $MirrorUrl
        }
        else {
            $TargetConfig.mirror_urls | ForEach-Object { [string]$_ }
        }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (@($candidates).Count -eq 0) {
        throw (New-PackageSourceAdapterException -Message 'nix catalog 未配置 mirror_urls' -ExitCode 10 -Code 'Blocked')
    }

    $probes = @($candidates | ForEach-Object {
            Test-NixPackageSourceUrl -Url $_ -TimeoutSeconds $TimeoutSeconds -Retry $Retry
        })
    $available = @($probes | Where-Object Success | Sort-Object ElapsedMs, Url)
    if (@($available).Count -eq 0) {
        throw (New-PackageSourceAdapterException -Message '所有 Nix binary cache 镜像均不可用' -ExitCode 10 -Code 'Blocked')
    }



    $trustedKeys = @($script:NixOfficialTrustedPublicKey)
    if ($TargetConfig.ContainsKey('trusted_public_keys')) {
        $trustedKeys = @($TargetConfig.trusted_public_keys | ForEach-Object { [string]$_ })
    }

    $path = Get-NixPackageSourcePath -TargetConfig $TargetConfig
    $existing = if (Test-Path -LiteralPath $path -PathType Leaf) {
        Get-Content -LiteralPath $path -Raw -Encoding utf8
    }
    else {
        $null
    }

    $merged = Merge-NixConfSubstituters -ExistingText $existing -MirrorUrls @($available | Select-Object -ExpandProperty Url) -TrustedPublicKeys $trustedKeys
    $changed = $existing -cne $merged
    if ($changed) {
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backupPath = '{0}.{1}.bak' -f $path, (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
            Copy-Item -LiteralPath $path -Destination $backupPath
            Set-PackageSourceFileMode -Path $backupPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        }
        $null = Write-PackageSourceTextAtomic -Path $path -Value $merged
        Set-PackageSourceFileMode -Path $path -Mode (
            [System.IO.UnixFileMode]::UserRead -bor
            [System.IO.UnixFileMode]::UserWrite -bor
            [System.IO.UnixFileMode]::GroupRead -bor
            [System.IO.UnixFileMode]::OtherRead
        )
        $null = Invoke-NixPackageSourceRestart
    }

    return [PSCustomObject]@{
        Source       = $available[0].Url
        Changed      = $changed
        ChsrcVersion = ''
        Message      = if ($changed) { 'Nix substituters 已更新（USTC → cache.nixos.org）' } else { 'Nix substituters 已满足' }
    }
}

Export-ModuleMember -Function @(
    'Get-NixPackageSourcePath'
    'Get-NixPackageSourceResourcePath'
    'Get-NixPackageSourceState'
    'Test-NixPackageSourceUrl'
    'Merge-NixConfSubstituters'
    'Invoke-NixPackageSourceApply'
    'Invoke-NixPackageSourceRestart'
    'Assert-NixPackageSourcePrivilege'
    'ConvertFrom-NixConfText'
)
