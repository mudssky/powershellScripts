[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PackageManager,
    [switch]$StartService,
    [switch]$Force
)

function Get-OllamaVersion {
    try {
        $cmd = Get-Command ollama -ErrorAction SilentlyContinue
        if ($null -eq $cmd) { return $null }
        $version = (& ollama --version) 2>$null
        if ([string]::IsNullOrWhiteSpace($version)) { return $null }
        return ($version.Trim())
    }
    catch { return $null }
}

function Test-OllamaInstalled {
    $exists = $false
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $exists = $true }
    $ver = Get-OllamaVersion
    [pscustomobject]@{ Installed = $exists; Version = $ver }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments
    )
    $output = @()
    try {
        $null = $Arguments
        if ($null -eq $Arguments) { $Arguments = @() }
        $result = & $Command @Arguments 2>&1
        $output = @($result)
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            throw "exit $code"
        }
        return [pscustomobject]@{ Success = $true; Output = $output; ExitCode = $code }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Output = $output; Error = $_.Exception.Message; ExitCode = $LASTEXITCODE }
    }
}

function Install-OllamaWindows {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$PackageManager)
    $pm = $PackageManager
    if ([string]::IsNullOrWhiteSpace($pm)) {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
        if ($null -ne $wingetCmd) { $pm = 'winget' }
        elseif ($null -ne $scoopCmd) { $pm = 'scoop' }
        else { $pm = '' }
    }
    switch ($pm) {
        'winget' {
            if ($PSCmdlet.ShouldProcess('Ollama', 'Install via winget')) {
                $r = Invoke-ExternalCommand -Command winget -Arguments @('install', '--id', 'Ollama.Ollama', '-e', '--source', 'winget')
                if (-not $r.Success) { throw "winget install failed: $($r.Error)" }
            }
        }
        'scoop' {
            if ($PSCmdlet.ShouldProcess('Ollama', 'Install via scoop')) {
                $r = Invoke-ExternalCommand -Command scoop -Arguments @('install', 'ollama')
                if (-not $r.Success) { throw "scoop install failed: $($r.Error)" }
            }
        }
        default {
            throw 'No available package manager (winget or scoop) found on Windows.'
        }
    }
}

function Install-OllamaLinux {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
    if ($null -eq $curlCmd) { throw 'curl is required on Linux.' }
    if ($PSCmdlet.ShouldProcess('Ollama', 'Install via official script')) {
        $r = Invoke-ExternalCommand -Command bash -Arguments @('-lc', 'curl -fsSL https://ollama.com/install.sh | sh')
        if (-not $r.Success) { throw "linux install failed: $($r.Error)" }
    }
}

function Install-OllamaMac {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    $brewCmd = Get-Command brew -ErrorAction SilentlyContinue
    if ($null -eq $brewCmd) { throw 'Homebrew is required on macOS.' }
    if ($PSCmdlet.ShouldProcess('Ollama', 'Install via Homebrew')) {
        $r = Invoke-ExternalCommand -Command brew -Arguments @('install', 'ollama')
        if (-not $r.Success) { throw "brew install failed: $($r.Error)" }
    }
}

function Start-OllamaService {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    if ($PSCmdlet.ShouldProcess('Ollama', 'Start serve')) {
        if ($IsWindows) {
            Start-Process -FilePath ollama -ArgumentList 'serve' -WindowStyle Hidden
        }
        else {
            Start-Process -FilePath ollama -ArgumentList 'serve' -NoNewWindow
        }
    }
}

function Install-Ollama {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$PackageManager,
        [switch]$StartService,
        [switch]$Force
    )
    try {
        $status = Test-OllamaInstalled
        if ($status.Installed -and -not $Force) {
            Write-Host "Ollama 已安装: $($status.Version)" -ForegroundColor Green
            if ($StartService) { Start-OllamaService }
            return
        }
        if ($IsWindows) { Install-OllamaWindows -PackageManager $PackageManager }
        elseif ($IsLinux) { Install-OllamaLinux }
        elseif ($IsMacOS) { Install-OllamaMac }
        else { throw '不支持的操作系统' }
        if (-not $WhatIfPreference) {
            $after = Test-OllamaInstalled
            if (-not $after.Installed) { throw '安装后未检测到 ollama' }
            Write-Host "Ollama 安装完成: $($after.Version)" -ForegroundColor Green
            if ($StartService) { Start-OllamaService }
        }
        else {
            Write-Host '跳过安装校验（WhatIf 模式）' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error $_.Exception.Message
        throw
    }
}

$invokeParams = @{ PackageManager = $PackageManager; StartService = $StartService; Force = $Force }
Install-Ollama @invokeParams
