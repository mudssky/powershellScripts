Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:SwitchMirrorsPath = Join-Path $script:RepoRoot 'scripts/pwsh/misc/Switch-Mirrors.ps1'
    $script:PackageSourcesModulePath = Join-Path $script:RepoRoot 'scripts/pwsh/misc/package-sources/PackageSources.psm1'
    $script:PwshPath = (Get-Process -Id $PID).Path
    $script:ExecutableFixtureRoot = if ($IsWindows) {
        $null
    }
    else {
        Join-Path $script:RepoRoot 'tests/.tmp-executables' ("package-sources-{0}" -f [Guid]::NewGuid())
    }
    if ($script:ExecutableFixtureRoot) {
        New-Item -ItemType Directory -Path $script:ExecutableFixtureRoot -Force | Out-Null
    }
    Import-Module $script:PackageSourcesModulePath -Force

    function Invoke-PackageSourceCli {
    <#
    .SYNOPSIS
        在隔离进程中执行换源公共入口。

    .DESCRIPTION
        捕获 stdout、stderr 与退出码，让测试通过真实 CLI 边界验证 JSON 合同，
        同时允许覆盖 HOME 和状态目录，避免触碰用户配置。

    .PARAMETER Arguments
        传给 Switch-Mirrors.ps1 的参数列表。

    .PARAMETER Environment
        需要注入子进程的环境变量。

    .OUTPUTS
        PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:PwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoLogo')
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($script:SwitchMirrorsPath)

    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[[string]$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }

    function Invoke-PackageSourceInProcess {
        <#
        .SYNOPSIS
            在当前 Pester 进程中执行 package source 领域入口。

        .DESCRIPTION
            复用原 CLI 测试的参数数组与 JSON 结果形态，但跳过重复的 pwsh 冷启动。
            仅用于不验证 Switch-Mirrors 参数绑定的领域行为用例。

        .PARAMETER Arguments
            与 Switch-Mirrors.ps1 新合同一致的参数列表。

        .PARAMETER Environment
            调用期间临时覆盖的进程环境变量。

        .OUTPUTS
            PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string[]]$Arguments,

            [hashtable]$Environment = @{}
        )

        $parameters = @{
            Action         = 'Plan'
            Mode           = 'Direct'
            Phase          = 'Runtime'
            Target         = @()
            TransactionId  = ''
            Selection      = 'Auto'
            MirrorUrl      = @()
            TimeoutSeconds = 5
            Retry          = 1
            Force          = $false
        }
        for ($index = 0; $index -lt $Arguments.Count; $index++) {
            $name = $Arguments[$index]
            switch ($name) {
                '-Action' { $parameters.Action = $Arguments[++$index] }
                '-Mode' { $parameters.Mode = $Arguments[++$index] }
                '-Phase' { $parameters.Phase = $Arguments[++$index] }
                '-Target' { $parameters.Target = @($Arguments[++$index]) }
                '-TransactionId' { $parameters.TransactionId = $Arguments[++$index] }
                '-Selection' { $parameters.Selection = $Arguments[++$index] }
                '-MirrorUrls' { $parameters.MirrorUrl = @($Arguments[++$index]) }
                '-TimeoutSec' { $parameters.TimeoutSeconds = [int]$Arguments[++$index] }
                '-Retry' { $parameters.Retry = [int]$Arguments[++$index] }
                '-Force' { $parameters.Force = $true }
                '-OutputFormat' { $index++ }
                default { throw "进程内测试入口不支持参数: $name" }
            }
        }

        $originalValues = @{}
        foreach ($entry in $Environment.GetEnumerator()) {
            $key = [string]$entry.Key
            $originalValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, [string]$entry.Value, 'Process')
        }

        try {
            $document = Invoke-PackageSourceAction @parameters
            return [PSCustomObject]@{
                ExitCode = [int]$document.ExitCode
                StdOut   = $document | ConvertTo-Json -Depth 20
                StdErr   = ''
            }
        }
        catch {
            $exitCode = if ($_.Exception.Data.Contains('ExitCode')) { [int]$_.Exception.Data['ExitCode'] } else { 1 }
            $errorCode = if ($_.Exception.Data.Contains('Code')) { [string]$_.Exception.Data['Code'] } else { 'Failed' }
            $document = [ordered]@{
                SchemaVersion = 1
                Action        = $parameters.Action
                Mode          = $parameters.Mode
                TransactionId = $parameters.TransactionId
                ExitCode      = $exitCode
                Results       = @()
                Error         = [ordered]@{
                    Code    = $errorCode
                    Message = $_.Exception.Message
                }
            }
            return [PSCustomObject]@{
                ExitCode = $exitCode
                StdOut   = $document | ConvertTo-Json -Depth 20
                StdErr   = $_.Exception.Message
            }
        }
        finally {
            foreach ($entry in $originalValues.GetEnumerator()) {
                [Environment]::SetEnvironmentVariable([string]$entry.Key, $entry.Value, 'Process')
            }
        }
    }

    function New-FakeChsrcScript {
        <#
        .SYNOPSIS
            创建测试使用的伪 chsrc 脚本。

        .DESCRIPTION
            模拟指定版本查询和 Homebrew managed-env 输出，只写子进程收到的隔离 HOME。

        .PARAMETER Root
            保存伪脚本的临时目录。

        .PARAMETER Version
            伪 chsrc 返回的语义版本。

        .OUTPUTS
            string。伪 chsrc PowerShell 脚本路径。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [string]$Version = '0.2.5'
        )

        if (-not $IsWindows) {
            # Linux Pester 容器将 /tmp 挂载为 noexec，因此可执行 fixture
            # 必须放在仓库挂载目录；状态与用户文件仍保持在 TestDrive。
            $path = Join-Path $script:ExecutableFixtureRoot 'fake-chsrc.sh'
            $scriptContent = @'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_CHSRC_LOG:-}" ]]; then
    printf '%s\n' "$*" >>"$FAKE_CHSRC_LOG"
fi

if [[ " ${*} " == *" --version "* ]]; then
    printf 'chsrc v__CHSRC_VERSION__ (test)\n'
    exit 0
fi

target=''
for argument in "$@"; do
    case "$argument" in
        brew|npm|ubuntu) target="$argument" ;;
    esac
done

case "$target" in
    brew)
        cat >"$HOME/.zshrc" <<'EOF'
# ------ chsrc BLOCK BEGIN for Homebrew ------
export HOMEBREW_BREW_GIT_REMOTE="https://mirror.example/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirror.example/git/homebrew/homebrew-core.git"
export HOMEBREW_API_DOMAIN="https://mirror.example/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirror.example/homebrew-bottles"
# ------ chsrc BLOCK ENDIN for Homebrew ------
EOF
        printf '选中镜像站: Test Mirror (test)\n'
        ;;
    npm)
        config_path="$HOME/.npmrc"
        temp_path="$config_path.tmp"
        found=false
        if [[ -f "$config_path" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" == registry=* ]]; then
                    printf 'registry=https://mirror.example/npm/\n' >>"$temp_path"
                    found=true
                else
                    printf '%s\n' "$line" >>"$temp_path"
                fi
            done <"$config_path"
        fi
        if [[ "$found" == false ]]; then
            printf 'registry=https://mirror.example/npm/\n' >>"$temp_path"
            [[ -f "$config_path" ]] && cat "$config_path" >>"$temp_path"
        fi
        mv "$temp_path" "$config_path"
        printf '选中镜像站: Test npm Mirror (test)\n'
        ;;
    ubuntu)
        sources_path="$POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT/etc/apt/sources.list"
        temp_path="$sources_path.tmp"
        sed 's|http://archive.ubuntu.com/ubuntu|https://mirror.example/ubuntu|g' "$sources_path" >"$temp_path"
        mv "$temp_path" "$sources_path"
        printf '选中镜像站: Test Ubuntu Mirror (test)\n'
        ;;
    *)
        printf 'unexpected fake chsrc arguments: %s\n' "$*" >&2
        exit 1
        ;;
esac
'@
            $scriptContent.Replace('__CHSRC_VERSION__', $Version) | Set-Content -LiteralPath $path -Encoding utf8NoBOM
            & chmod '+x' $path
            if ($LASTEXITCODE -ne 0) {
                throw "无法设置 fake chsrc 执行权限: $path"
            }
            return $path
        }

        $path = Join-Path $Root 'fake-chsrc.ps1'
        $scriptContent = @'
param([Parameter(ValueFromRemainingArguments)][string[]]$RemainingArguments)

if (-not [string]::IsNullOrWhiteSpace($env:FAKE_CHSRC_LOG)) {
    Add-Content -LiteralPath $env:FAKE_CHSRC_LOG -Value ($RemainingArguments -join ' ')
}

if ($RemainingArguments -contains '--version') {
    Write-Output 'chsrc v__CHSRC_VERSION__ (test)'
    return
}

if ($RemainingArguments.Count -ge 2 -and $RemainingArguments[0] -eq 'set' -and $RemainingArguments -contains 'brew') {
    $content = @(
        '# ------ chsrc BLOCK BEGIN for Homebrew ------'
        'export HOMEBREW_BREW_GIT_REMOTE="https://mirror.example/git/homebrew/brew.git"'
        'export HOMEBREW_CORE_GIT_REMOTE="https://mirror.example/git/homebrew/homebrew-core.git"'
        'export HOMEBREW_API_DOMAIN="https://mirror.example/homebrew-bottles/api"'
        'export HOMEBREW_BOTTLE_DOMAIN="https://mirror.example/homebrew-bottles"'
        '# ------ chsrc BLOCK ENDIN for Homebrew ------'
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $env:HOME '.zshrc') -Value $content -Encoding utf8NoBOM
    Write-Output '选中镜像站: Test Mirror (test)'
    return
}

if ($RemainingArguments.Count -ge 2 -and $RemainingArguments[0] -eq 'set' -and $RemainingArguments -contains 'npm') {
    $configPath = Join-Path $env:HOME '.npmrc'
    $content = if (Test-Path -LiteralPath $configPath) {
        Get-Content -LiteralPath $configPath -Raw
    }
    else {
        ''
    }
    if ($content -match '(?m)^registry=') {
        $content = [regex]::Replace($content, '(?m)^registry=.*$', 'registry=https://mirror.example/npm/')
    }
    else {
        $content = "registry=https://mirror.example/npm/$([Environment]::NewLine)$content"
    }
    Set-Content -LiteralPath $configPath -Value $content -Encoding utf8NoBOM -NoNewline
    Write-Output '选中镜像站: Test npm Mirror (test)'
    return
}

if ($RemainingArguments.Count -ge 2 -and $RemainingArguments[0] -eq 'set' -and $RemainingArguments -contains 'ubuntu') {
    $systemRoot = $env:POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT
    $sourcesPath = Join-Path $systemRoot 'etc/apt/sources.list'
    $content = Get-Content -LiteralPath $sourcesPath -Raw
    $content = $content.Replace('http://archive.ubuntu.com/ubuntu', 'https://mirror.example/ubuntu')
    Set-Content -LiteralPath $sourcesPath -Value $content -Encoding utf8NoBOM -NoNewline
    Write-Output '选中镜像站: Test Ubuntu Mirror (test)'
    return
}

throw "unexpected fake chsrc arguments: $($RemainingArguments -join ' ')"
'@
        $scriptContent.Replace('__CHSRC_VERSION__', $Version) | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        return $path
    }

    function New-FakeNpmScript {
        <#
        .SYNOPSIS
            创建测试使用的伪 npm 脚本。

        .DESCRIPTION
            只实现 package source adapter 所需的 userconfig 与 registry 读取命令。

        .PARAMETER Root
            保存伪脚本的临时目录。

        .OUTPUTS
            string。伪 npm PowerShell 脚本路径。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Root
        )

        if (-not $IsWindows) {
            $path = Join-Path $script:ExecutableFixtureRoot 'fake-npm.sh'
            @'
#!/usr/bin/env bash
set -euo pipefail

command_text="$*"
if [[ "$command_text" == 'config get userconfig' ]]; then
    printf '%s\n' "$HOME/.npmrc"
    exit 0
fi

if [[ "$command_text" == 'config get registry' ]]; then
    config_path="$HOME/.npmrc"
    if [[ -f "$config_path" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == registry=* ]]; then
                printf '%s\n' "${line#registry=}"
                exit 0
            fi
        done <"$config_path"
    fi
    printf 'https://registry.npmjs.org/\n'
    exit 0
fi

printf 'unexpected fake npm arguments: %s\n' "$command_text" >&2
exit 1
'@ | Set-Content -LiteralPath $path -Encoding utf8NoBOM
            & chmod '+x' $path
            if ($LASTEXITCODE -ne 0) {
                throw "无法设置 fake npm 执行权限: $path"
            }
            return $path
        }

        $path = Join-Path $Root 'fake-npm.ps1'
        @'
param([Parameter(ValueFromRemainingArguments)][string[]]$RemainingArguments)

if (($RemainingArguments -join ' ') -eq 'config get userconfig') {
    Write-Output (Join-Path $env:HOME '.npmrc')
    return
}

if (($RemainingArguments -join ' ') -eq 'config get registry') {
    $configPath = Join-Path $env:HOME '.npmrc'
    if (Test-Path -LiteralPath $configPath) {
        $match = [regex]::Match((Get-Content -LiteralPath $configPath -Raw), '(?m)^registry=(?<value>[^\r\n]+)')
        if ($match.Success) {
            Write-Output $match.Groups['value'].Value
            return
        }
    }
    Write-Output 'https://registry.npmjs.org/'
    return
}

throw "unexpected fake npm arguments: $($RemainingArguments -join ' ')"
'@ | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        return $path
    }

    function Set-PackageSourceNetworkGuard {
        <#
        .SYNOPSIS
            为当前测试注册默认失败的网络边界 Mock。

        .OUTPUTS
            None。未被具体用例覆盖的网络访问会立即使测试失败。
        #>
        [CmdletBinding()]
        param()

        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            throw '测试未声明的 PackageSources 网络访问'
        }

        # DockerAdapter 由 PackageSources 在首次领域调用时惰性加载；首个 BeforeEach
        # 不应为了注册 Mock 提前改变生产模块的加载时序。
        if (Get-Module -Name DockerAdapter) {
            Mock -CommandName Invoke-WebRequest -ModuleName DockerAdapter -MockWith {
                throw '测试未声明的 DockerAdapter 网络访问'
            }
        }
    }
}

AfterAll {
    if ($script:ExecutableFixtureRoot) {
        Remove-Item -LiteralPath $script:ExecutableFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# brew 等目标走 ManagedEnvAdapter，其写 .zshrc/UnixFileMode 且依赖 zsh，无法在原生 Windows 运行，
# 因此这些用例在 Windows 主机跳过（与 PackageSourceBootstrap.Tests 的非 Windows 防护语义一致）。
Describe 'Switch-Mirrors package source CLI' {
    BeforeEach {
        Set-PackageSourceNetworkGuard
    }

    It 'Direct 计划返回稳定 JSON 且不创建事务状态' {
        $homePath = Join-Path $TestDrive 'home'
        $statePath = Join-Path $TestDrive 'state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null

        $result = Invoke-PackageSourceCli -Arguments @(
            '-Action', 'Plan',
            '-Mode', 'Direct',
            '-Target', 'npm',
            '-OutputFormat', 'Json'
        ) -Environment @{
            HOME                                         = $homePath
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $document = $result.StdOut | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        $document.Action | Should -Be 'Plan'
        $document.Mode | Should -Be 'Direct'
        @($document.Results).Count | Should -Be 1
        $document.Results[0].Target | Should -Be 'npm'
        $document.Results[0].Status | Should -Be 'Direct'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It '缺少 Target 时返回结构化参数错误' {
        $result = Invoke-PackageSourceCli -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-OutputFormat', 'Json'
        )

        $result.ExitCode | Should -Be 2
        $document = $result.StdOut | ConvertFrom-Json
        $document.ExitCode | Should -Be 2
        $document.Error.Code | Should -Be 'InvalidArguments'
        $document.Error.Message | Should -Match 'Target 为必填参数'
    }

    It 'China 计划只返回 adapter 计划且不创建事务状态' {
        $homePath = Join-Path $TestDrive 'china-plan-home'
        $statePath = Join-Path $TestDrive 'china-plan-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null

        $result = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Plan',
            '-Mode', 'China',
            '-Target', 'npm',
            '-OutputFormat', 'Json'
        ) -Environment @{
            HOME                                         = $homePath
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $document = $result.StdOut | ConvertFrom-Json
        $document.Results[0].Status | Should -Be 'Planned'
        $document.Results[0].Adapter | Should -Be 'chsrc'
        $document.Results[0].Persistent | Should -BeTrue
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It 'Apply -WhatIf 映射为 Plan 且不创建事务' {
        $statePath = Join-Path $TestDrive 'whatif-state'

        $result = Invoke-PackageSourceCli -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'whatif-test',
            '-WhatIf',
            '-OutputFormat', 'Json'
        ) -Environment @{
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $document = $result.StdOut | ConvertFrom-Json
        $document.Action | Should -Be 'Plan'
        $document.Results[0].Status | Should -Be 'Planned'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It '旧 Docker -WhatIf 映射为 DryRun 且不创建事务' {
        $statePath = Join-Path $TestDrive 'legacy-whatif-state'

        $result = Invoke-PackageSourceCli -Arguments @(
            '-Target', 'docker',
            '-UseChinaMirror',
            '-WhatIf'
        ) -Environment @{
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $result.StdOut | Should -Match '\[Planned\] docker'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It 'winget Stage 1 计划明确返回 Unsupported' {
        $statePath = Join-Path $TestDrive 'winget-plan-state'

        $result = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Plan',
            '-Mode', 'China',
            '-Target', 'winget',
            '-OutputFormat', 'Json'
        ) -Environment @{
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 10
        $document = $result.StdOut | ConvertFrom-Json
        $document.ExitCode | Should -Be 10
        $document.Results[0].Status | Should -Be 'Unsupported'
        $document.Results[0].Message | Should -Match 'Microsoft\.WinGet\.Client'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It 'China 应用 Homebrew 只写受管 env 并创建持久事务' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'brew-home'
        $statePath = Join-Path $TestDrive 'brew-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive

        $result = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'brew-china-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
        }

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $document = $result.StdOut | ConvertFrom-Json
        $document.Results[0].Status | Should -Be 'Applied'
        $document.Results[0].Persistent | Should -BeTrue
        $document.Results[0].TransactionId | Should -Be 'brew-china-test'

        $managedEnvPath = Join-Path $homePath '.config/powershellScripts/package-sources.env'
        Test-Path -LiteralPath $managedEnvPath | Should -BeTrue
        $managedEnv = Get-Content -LiteralPath $managedEnvPath -Raw
        $managedEnv | Should -Match 'HOMEBREW_BOTTLE_DOMAIN="https://mirror\.example/homebrew-bottles"'
        Test-Path -LiteralPath (Join-Path $homePath '.zshrc') | Should -BeFalse

        $manifestPath = Join-Path $statePath 'brew-china-test/manifest.json'
        Test-Path -LiteralPath $manifestPath | Should -BeTrue
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.Status | Should -Be 'Active'
        $manifest.Mode | Should -Be 'China'
        @($manifest.Targets).Count | Should -Be 1
    }

    It 'Restore 恢复事务前不存在的受管 env 文件' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'restore-home'
        $statePath = Join-Path $TestDrive 'restore-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'brew-restore-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr

        $restoreResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Restore',
            '-TransactionId', 'brew-restore-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $restoreResult.ExitCode | Should -Be 0 -Because $restoreResult.StdErr
        $document = $restoreResult.StdOut | ConvertFrom-Json
        $document.Results[0].Target | Should -Be 'brew'
        $document.Results[0].Status | Should -Be 'Restored'
        Test-Path -LiteralPath (Join-Path $homePath '.config/powershellScripts/package-sources.env') | Should -BeFalse

        $secondRestoreResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Restore',
            '-TransactionId', 'brew-restore-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $secondRestoreResult.ExitCode | Should -Be 0 -Because $secondRestoreResult.StdErr
        ($secondRestoreResult.StdOut | ConvertFrom-Json).Results[0].Message | Should -Match '无需重复写入'

        $manifestPath = Join-Path $statePath 'brew-restore-test/manifest.json'
        (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).Status | Should -Be 'Restored'
    }

    It 'Restore 检测到 drift 时拒绝覆盖并返回 Blocked' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'drift-home'
        $statePath = Join-Path $TestDrive 'drift-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'brew-drift-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr

        $managedEnvPath = Join-Path $homePath '.config/powershellScripts/package-sources.env'
        Add-Content -LiteralPath $managedEnvPath -Value '# user change after apply'
        $driftedContent = Get-Content -LiteralPath $managedEnvPath -Raw

        $statusResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Status',
            '-TransactionId', 'brew-drift-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $statusResult.ExitCode | Should -Be 10
        $statusDocument = $statusResult.StdOut | ConvertFrom-Json
        $statusDocument.ExitCode | Should -Be 10
        $statusDocument.Results[0].Status | Should -Be 'Drifted'

        $restoreResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Restore',
            '-TransactionId', 'brew-drift-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $restoreResult.ExitCode | Should -Be 10
        $document = $restoreResult.StdOut | ConvertFrom-Json
        $document.ExitCode | Should -Be 10
        $document.Error.Code | Should -Be 'Blocked'
        Get-Content -LiteralPath $managedEnvPath -Raw | Should -BeExactly $driftedContent

        $manifestPath = Join-Path $statePath 'brew-drift-test/manifest.json'
        (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).Status | Should -Be 'Drifted'
    }

    It 'China 重复 Apply 复用 active transaction 且不再次调用 chsrc' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'idempotent-home'
        $statePath = Join-Path $TestDrive 'idempotent-state'
        $chsrcLogPath = Join-Path $TestDrive 'idempotent-chsrc.log'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
            FAKE_CHSRC_LOG                                = $chsrcLogPath
        }
        $arguments = @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'brew-idempotent-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        )

        $firstResult = Invoke-PackageSourceInProcess -Arguments $arguments -Environment $environment
        $secondResult = Invoke-PackageSourceInProcess -Arguments $arguments -Environment $environment

        $firstResult.ExitCode | Should -Be 0 -Because $firstResult.StdErr
        $secondResult.ExitCode | Should -Be 0 -Because $secondResult.StdErr
        ($secondResult.StdOut | ConvertFrom-Json).Results[0].Status | Should -Be 'AlreadyApplied'
        @((Get-Content -LiteralPath $chsrcLogPath) | Where-Object { $_ -match '^set ' }).Count | Should -Be 1

        $managedEnvPath = Join-Path $homePath '.config/powershellScripts/package-sources.env'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $managedEnvPath) -Filter 'package-sources.env.*.bak').Count | Should -Be 0
        $manifestPath = Join-Path $statePath 'brew-idempotent-test/manifest.json'
        @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).Targets).Count | Should -Be 1
    }

    It 'npm Apply 不泄露 token 且 Restore 精确恢复原配置' {
        $homePath = Join-Path $TestDrive 'npm-home'
        $statePath = Join-Path $TestDrive 'npm-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $fakeNpmPath = New-FakeNpmScript -Root $TestDrive
        $npmConfigPath = Join-Path $homePath '.npmrc'
        $originalContent = @(
            'registry=https://custom.example/npm/'
            'always-auth=true'
            '//custom.example/npm/:_authToken=super-secret-token'
            ''
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $npmConfigPath -Value $originalContent -Encoding utf8NoBOM -NoNewline
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
            POWERSHELL_SCRIPTS_NPM_PATH                  = $fakeNpmPath
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'npm',
            '-TransactionId', 'npm-secret-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr
        $applyResult.StdOut | Should -Not -Match 'super-secret-token'
        $updatedContent = Get-Content -LiteralPath $npmConfigPath -Raw
        $updatedContent | Should -Match 'registry=https://mirror\.example/npm/'
        $updatedContent | Should -Match '_authToken=super-secret-token'

        $manifestPath = Join-Path $statePath 'npm-secret-test/manifest.json'
        Get-Content -LiteralPath $manifestPath -Raw | Should -Not -Match 'super-secret-token'
        $snapshotPath = Get-ChildItem -LiteralPath (Join-Path $statePath 'npm-secret-test/snapshots') -Filter 'npm-*.snapshot' | Select-Object -First 1
        Get-Content -LiteralPath $snapshotPath.FullName -Raw | Should -Match 'super-secret-token'
        if (-not $IsWindows) {
            [System.IO.File]::GetUnixFileMode($snapshotPath.FullName) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        }

        $restoreResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Restore',
            '-TransactionId', 'npm-secret-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $restoreResult.ExitCode | Should -Be 0 -Because $restoreResult.StdErr
        Get-Content -LiteralPath $npmConfigPath -Raw | Should -BeExactly $originalContent
    }

    It 'Status 只读报告 active transaction 与回滚入口' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'status-home'
        $statePath = Join-Path $TestDrive 'status-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'brew-status-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr

        $statusResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Status',
            '-TransactionId', 'brew-status-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $statusResult.ExitCode | Should -Be 0 -Because $statusResult.StdErr
        $document = $statusResult.StdOut | ConvertFrom-Json
        $document.Action | Should -Be 'Status'
        $document.Results[0].Status | Should -Be 'Active'
        $document.Results[0].Rollback | Should -Match 'Restore -TransactionId brew-status-test'
        (Get-Content -LiteralPath (Join-Path $statePath 'brew-status-test/manifest.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Active'
    }

    It 'Ensure 将后出现的 npm 补进既有 China 事务' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'ensure-home'
        $statePath = Join-Path $TestDrive 'ensure-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $fakeNpmPath = New-FakeNpmScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
            POWERSHELL_SCRIPTS_NPM_PATH                  = $fakeNpmPath
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'ensure-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr

        $ensureResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Ensure',
            '-Target', 'npm',
            '-TransactionId', 'ensure-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $ensureResult.ExitCode | Should -Be 0 -Because $ensureResult.StdErr
        $document = $ensureResult.StdOut | ConvertFrom-Json
        $document.Mode | Should -Be 'China'
        $document.Results[0].Target | Should -Be 'npm'
        $document.Results[0].Status | Should -Be 'Applied'
        $manifest = Get-Content -LiteralPath (Join-Path $statePath 'ensure-test/manifest.json') -Raw | ConvertFrom-Json
        @($manifest.Targets | Select-Object -ExpandProperty Target) | Should -Be @('brew', 'npm')
    }

    It '未验证 adapter 返回 Unsupported 且不创建事务' {
        $homePath = Join-Path $TestDrive 'unsupported-home'
        $statePath = Join-Path $TestDrive 'unsupported-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null

        $result = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'uv',
            '-TransactionId', 'unsupported-test',
            '-OutputFormat', 'Json'
        ) -Environment @{
            HOME                                         = $homePath
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
        }

        $result.ExitCode | Should -Be 10
        $document = $result.StdOut | ConvertFrom-Json
        $document.ExitCode | Should -Be 10
        $document.Results[0].Target | Should -Be 'uv'
        $document.Results[0].Status | Should -Be 'Unsupported'
        $document.Results[0].Message | Should -Match '结构化 TOML'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It '低于 catalog 下限的 chsrc 返回 Blocked 且不创建事务' {
        $homePath = Join-Path $TestDrive 'old-chsrc-home'
        $statePath = Join-Path $TestDrive 'old-chsrc-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive -Version '0.2.2'

        $result = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'brew',
            '-TransactionId', 'old-chsrc-test',
            '-OutputFormat', 'Json'
        ) -Environment @{
            HOME                                         = $homePath
            XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
        }

        $result.ExitCode | Should -Be 10
        $document = $result.StdOut | ConvertFrom-Json
        $document.Error.Code | Should -Be 'Blocked'
        $document.Error.Message | Should -Match 'chsrc 版本过低: 0\.2\.2，最低要求 0\.2\.5'
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It '状态锁被占用时返回 Blocked 且不创建事务' {
        $homePath = Join-Path $TestDrive 'lock-home'
        $statePath = Join-Path $TestDrive 'lock-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        New-Item -ItemType Directory -Path $statePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $lockPath = Join-Path $statePath '.lock'
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        try {
            $result = Invoke-PackageSourceInProcess -Arguments @(
                '-Action', 'Apply',
                '-Mode', 'China',
                '-Target', 'brew',
                '-TransactionId', 'lock-test',
                '-Selection', 'First',
                '-OutputFormat', 'Json'
            ) -Environment @{
                HOME                                         = $homePath
                XDG_CONFIG_HOME                              = (Join-Path $homePath '.config')
                XDG_STATE_HOME                               = $statePath
                POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
                POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
            }
        }
        finally {
            $lockStream.Dispose()
        }

        $result.ExitCode | Should -Be 10
        ($result.StdOut | ConvertFrom-Json).Error.Code | Should -Be 'Blocked'
        Test-Path -LiteralPath (Join-Path $statePath 'lock-test') | Should -BeFalse
    }

    It 'Ubuntu system adapter 使用文件 snapshot 恢复原 sources' {
        $homePath = Join-Path $TestDrive 'ubuntu-home'
        $statePath = Join-Path $TestDrive 'ubuntu-state'
        $systemRoot = Join-Path $TestDrive 'ubuntu-root'
        $sourcesPath = Join-Path $systemRoot 'etc/apt/sources.list'
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourcesPath) -Force | Out-Null
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $originalContent = 'deb http://archive.ubuntu.com/ubuntu noble main' + [Environment]::NewLine
        Set-Content -LiteralPath $sourcesPath -Value $originalContent -Encoding utf8NoBOM -NoNewline
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $environment = @{
            HOME                                         = $homePath
            XDG_STATE_HOME                               = $statePath
            POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT = $statePath
            POWERSHELL_SCRIPTS_CHSRC_PATH                = $fakeChsrcPath
            POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT        = $systemRoot
        }

        $applyResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Apply',
            '-Mode', 'China',
            '-Target', 'ubuntu',
            '-TransactionId', 'ubuntu-system-test',
            '-Selection', 'First',
            '-OutputFormat', 'Json'
        ) -Environment $environment

        $applyResult.ExitCode | Should -Be 0 -Because $applyResult.StdErr
        Get-Content -LiteralPath $sourcesPath -Raw | Should -Match 'https://mirror\.example/ubuntu'
        $restoreResult = Invoke-PackageSourceInProcess -Arguments @(
            '-Action', 'Restore',
            '-TransactionId', 'ubuntu-system-test',
            '-OutputFormat', 'Json'
        ) -Environment $environment
        $restoreResult.ExitCode | Should -Be 0 -Because $restoreResult.StdErr
        Get-Content -LiteralPath $sourcesPath -Raw | Should -BeExactly $originalContent
    }
}

# Auto 策略里以 brew 为目标的用例同样依赖 ManagedEnvAdapter，在原生 Windows 跳过（见上方说明）。
Describe 'Package source Auto policy' {
    BeforeEach {
        Set-PackageSourceNetworkGuard
    }

    It '官方端点健康时保持官方源且不创建事务' {
        $homePath = Join-Path $TestDrive 'auto-healthy-home'
        $statePath = Join-Path $TestDrive 'auto-healthy-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $brewEnvNames = @(
            'HOMEBREW_BREW_GIT_REMOTE'
            'HOMEBREW_CORE_GIT_REMOTE'
            'HOMEBREW_API_DOMAIN'
            'HOMEBREW_BOTTLE_DOMAIN'
        )
        $variableNames = @('HOME', 'XDG_CONFIG_HOME', 'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT') + $brewEnvNames
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $homePath '.config'), 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        foreach ($name in $brewEnvNames) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            [PSCustomObject]@{ StatusCode = 200 }
        }

        try {
            $document = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target brew
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $document.ExitCode | Should -Be 0
        $document.TransactionId | Should -BeNullOrEmpty
        $document.Results[0].Status | Should -Be 'Official'
        $document.Results[0].Persistent | Should -BeFalse
        Test-Path -LiteralPath $statePath | Should -BeFalse
    }

    It '健康的 unmanaged npm source 保持 External 且不调用 chsrc' {
        $homePath = Join-Path $TestDrive 'auto-external-home'
        $statePath = Join-Path $TestDrive 'auto-external-state'
        $chsrcLogPath = Join-Path $TestDrive 'auto-external-chsrc.log'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $homePath '.npmrc') -Value 'registry=https://custom.example/npm/' -Encoding utf8NoBOM
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $fakeNpmPath = New-FakeNpmScript -Root $TestDrive
        $variableNames = @(
            'HOME',
            'XDG_CONFIG_HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_CHSRC_PATH',
            'POWERSHELL_SCRIPTS_NPM_PATH',
            'FAKE_CHSRC_LOG'
        )
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $homePath '.config'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_CHSRC_PATH', $fakeChsrcPath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_NPM_PATH', $fakeNpmPath, 'Process')
        [Environment]::SetEnvironmentVariable('FAKE_CHSRC_LOG', $chsrcLogPath, 'Process')
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            [PSCustomObject]@{ StatusCode = 200 }
        }

        try {
            $document = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target npm -TransactionId 'auto-external-test'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $document.Results[0].Status | Should -Be 'External'
        $document.Results[0].Source | Should -Be 'https://custom.example/npm/'
        Test-Path -LiteralPath $statePath | Should -BeFalse
        Test-Path -LiteralPath $chsrcLogPath | Should -BeFalse
    }

    It '不可用的 unmanaged npm source 返回 ExternalUnavailable 且不覆盖' {
        $homePath = Join-Path $TestDrive 'auto-external-unavailable-home'
        $statePath = Join-Path $TestDrive 'auto-external-unavailable-state'
        $chsrcLogPath = Join-Path $TestDrive 'auto-external-unavailable-chsrc.log'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $homePath '.npmrc') -Value 'registry=https://custom.example/npm/' -Encoding utf8NoBOM
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $fakeNpmPath = New-FakeNpmScript -Root $TestDrive
        $variableNames = @(
            'HOME',
            'XDG_CONFIG_HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_CHSRC_PATH',
            'POWERSHELL_SCRIPTS_NPM_PATH',
            'FAKE_CHSRC_LOG'
        )
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $homePath '.config'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_CHSRC_PATH', $fakeChsrcPath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_NPM_PATH', $fakeNpmPath, 'Process')
        [Environment]::SetEnvironmentVariable('FAKE_CHSRC_LOG', $chsrcLogPath, 'Process')
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            throw 'mock external endpoint unavailable'
        }

        try {
            $document = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target npm -TransactionId 'auto-external-unavailable-test'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $document.ExitCode | Should -Be 10
        $document.TransactionId | Should -BeNullOrEmpty
        $document.Results[0].Status | Should -Be 'ExternalUnavailable'
        $document.Results[0].Source | Should -Be 'https://custom.example/npm/'
        Get-Content -LiteralPath (Join-Path $homePath '.npmrc') -Raw | Should -Match 'https://custom\.example/npm/'
        Test-Path -LiteralPath $statePath | Should -BeFalse
        Test-Path -LiteralPath $chsrcLogPath | Should -BeFalse
    }

    It '官方端点连续失败时创建可恢复的临时事务' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'auto-fallback-home'
        $statePath = Join-Path $TestDrive 'auto-fallback-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $brewEnvNames = @(
            'HOMEBREW_BREW_GIT_REMOTE'
            'HOMEBREW_CORE_GIT_REMOTE'
            'HOMEBREW_API_DOMAIN'
            'HOMEBREW_BOTTLE_DOMAIN'
        )
        $variableNames = @(
            'HOME',
            'XDG_CONFIG_HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_CHSRC_PATH'
        ) + $brewEnvNames
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $homePath '.config'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_CHSRC_PATH', $fakeChsrcPath, 'Process')
        foreach ($name in $brewEnvNames) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            throw 'mock official endpoint unavailable'
        }

        try {
            $applyDocument = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target brew -TransactionId 'brew-auto-test' -Selection First
            $restoreDocument = Invoke-PackageSourceAction -Action Restore -TransactionId 'brew-auto-test'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $applyDocument.Results[0].Status | Should -Be 'Applied'
        $applyDocument.Results[0].Persistent | Should -BeFalse
        $applyDocument.TransactionId | Should -Be 'brew-auto-test'
        $restoreDocument.Results[0].Status | Should -Be 'Restored'
        Test-Path -LiteralPath (Join-Path $homePath '.config/powershellScripts/package-sources.env') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $statePath 'brew-auto-test/manifest.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Restored'
    }

    It 'Auto owner 已退出时 Status 报告 Orphaned' -Skip:$IsWindows {
        $homePath = Join-Path $TestDrive 'auto-orphan-home'
        $statePath = Join-Path $TestDrive 'auto-orphan-state'
        New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        $fakeChsrcPath = New-FakeChsrcScript -Root $TestDrive
        $brewEnvNames = @(
            'HOMEBREW_BREW_GIT_REMOTE'
            'HOMEBREW_CORE_GIT_REMOTE'
            'HOMEBREW_API_DOMAIN'
            'HOMEBREW_BOTTLE_DOMAIN'
        )
        $variableNames = @(
            'HOME',
            'XDG_CONFIG_HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_CHSRC_PATH'
        ) + $brewEnvNames
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $homePath '.config'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_CHSRC_PATH', $fakeChsrcPath, 'Process')
        foreach ($name in $brewEnvNames) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            throw 'mock official endpoint unavailable'
        }

        try {
            $null = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target brew -TransactionId 'auto-orphan-test' -Selection First
            $manifestPath = Join-Path $statePath 'auto-orphan-test/manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.OwnerPid = 999999
            $manifest.OwnerProcessStartUtc = '2000-01-01T00:00:00.0000000Z'
            $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

            $statusDocument = Invoke-PackageSourceAction -Action Status -TransactionId 'auto-orphan-test'
            Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
            $nextDocument = Invoke-PackageSourceAction -Action Apply -Mode Auto -Target brew -TransactionId 'auto-after-orphan'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $statusDocument.Results[0].Status | Should -Be 'Orphaned'
        $statusDocument.ExitCode | Should -Be 10
        $nextDocument.Results[0].Status | Should -Be 'Official'
        Test-Path -LiteralPath (Join-Path $homePath '.config/powershellScripts/package-sources.env') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $statePath 'auto-orphan-test/manifest.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Restored'
    }
}

Describe 'Docker package source adapter' {
    BeforeEach {
        Set-PackageSourceNetworkGuard
    }

    It '保留 daemon JSON 其它字段并可通过事务恢复' {
        $homePath = Join-Path $TestDrive 'docker-home'
        $statePath = Join-Path $TestDrive 'docker-state'
        $daemonPath = Join-Path $TestDrive 'docker/daemon.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $daemonPath) -Force | Out-Null
        $originalContent = @{
            'log-driver' = 'json-file'
            features     = @{ containerdSnapshotter = $true }
        } | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath $daemonPath -Value $originalContent -Encoding utf8NoBOM

        $variableNames = @(
            'HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_DOCKER_DAEMON_PATH',
            'POWERSHELL_SCRIPTS_SKIP_DOCKER_RESTART'
        )
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_DOCKER_DAEMON_PATH', $daemonPath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_DOCKER_RESTART', '1', 'Process')
        Mock -CommandName Invoke-WebRequest -ModuleName DockerAdapter -MockWith {
            [PSCustomObject]@{ StatusCode = 401 }
        }

        try {
            $applyDocument = Invoke-PackageSourceAction -Action Apply -Mode China -Target docker -TransactionId 'docker-adapter-test'
            $updated = Get-Content -LiteralPath $daemonPath -Raw | ConvertFrom-Json
            $restoreDocument = Invoke-PackageSourceAction -Action Restore -TransactionId 'docker-adapter-test'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        $applyDocument.Results[0].Status | Should -Be 'Applied'
        $updated.'log-driver' | Should -Be 'json-file'
        $updated.features.containerdSnapshotter | Should -BeTrue
        @($updated.'registry-mirrors').Count | Should -Be 2
        $restoreDocument.Results[0].Status | Should -Be 'Restored'
        Get-Content -LiteralPath $daemonPath -Raw | Should -BeExactly ($originalContent + [Environment]::NewLine)
    }

    It 'Auto adapter 写入后失败时立即恢复 daemon 配置' {
        $homePath = Join-Path $TestDrive 'docker-auto-home'
        $statePath = Join-Path $TestDrive 'docker-auto-state'
        $daemonPath = Join-Path $TestDrive 'docker-auto/daemon.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $daemonPath) -Force | Out-Null
        $originalContent = '{"log-driver":"json-file"}' + [Environment]::NewLine
        Set-Content -LiteralPath $daemonPath -Value $originalContent -Encoding utf8NoBOM -NoNewline

        $variableNames = @(
            'HOME',
            'XDG_STATE_HOME',
            'POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT',
            'POWERSHELL_SCRIPTS_DOCKER_DAEMON_PATH',
            'POWERSHELL_SCRIPTS_DOCKER_RESTART_FAIL'
        )
        $originalValues = @{}
        foreach ($name in $variableNames) {
            $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_STATE_HOME', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', $statePath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_DOCKER_DAEMON_PATH', $daemonPath, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_DOCKER_RESTART_FAIL', '1', 'Process')
        Mock -CommandName Invoke-WebRequest -ModuleName PackageSources -MockWith {
            throw 'mock official endpoint unavailable'
        }
        Mock -CommandName Invoke-WebRequest -ModuleName DockerAdapter -MockWith {
            [PSCustomObject]@{ StatusCode = 200 }
        }

        try {
            {
                Invoke-PackageSourceAction -Action Apply -Mode Auto -Target docker -TransactionId 'docker-auto-failure'
            } | Should -Throw '*Docker 重启失败*'
        }
        finally {
            foreach ($name in $variableNames) {
                [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
            }
        }

        Get-Content -LiteralPath $daemonPath -Raw | Should -BeExactly $originalContent
        (Get-Content -LiteralPath (Join-Path $statePath 'docker-auto-failure/manifest.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Restored'
    }
}
