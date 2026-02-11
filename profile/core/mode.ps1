function Test-EnvSwitchEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $rawValue = [System.Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $rawValue) { return $false }
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

    $rawValue = [System.Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $rawValue) { return $false }
    return -not [string]::IsNullOrWhiteSpace($rawValue)
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
