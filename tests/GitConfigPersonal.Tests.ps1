Set-StrictMode -Version Latest

# -Skip 条件在 Discovery 阶段求值，早于 BeforeAll，因此 git 可用性必须在顶层判定。
$script:HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

BeforeAll {
    # 通过环境变量跳过脚本文件底部的主入口，允许测试直接调用内部函数。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/misc/gitconfig_personal.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_GITCONFIG_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_GITCONFIG_MAIN = '1'

    . $script:ScriptPath

    function New-TestConfigFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [hashtable]$Overrides = @{}
        )

        $document = @{
            profiles = @{
                personal = @{ name = 'personal-user'; email = 'personal@example.com' }
                company  = @{ name = 'company-user'; email = 'company@example.com'; hosts = @('git.example.com') }
            }
            default  = 'personal'
        }

        foreach ($entry in $Overrides.GetEnumerator()) {
            $document[$entry.Key] = $entry.Value
        }

        $document | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
        return $Path
    }

    function New-TestIdentity {
        param(
            [string]$Name = 'company-user',
            [string]$Email = 'company@example.com',
            [string]$EmailOrigin = '/home/tester/.gitconfig-company',
            [string]$RemoteUrl = 'git@git.example.com:group/repo.git',
            [switch]$HasLocalOverride
        )

        return @{
            Name             = $Name
            Email            = $Email
            EmailOrigin      = $EmailOrigin
            RemoteUrl        = $RemoteUrl
            HasLocalOverride = [bool]$HasLocalOverride
        }
    }
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_GITCONFIG_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_GITCONFIG_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'Get-GitRemoteHost' {
    It 'extracts host from scp shorthand with a group path' {
        Get-GitRemoteHost -RemoteUrl 'git@gitlab.example.com:group/repo.git' | Should -Be 'gitlab.example.com'
    }

    It 'extracts host from scp shorthand without a group path' {
        Get-GitRemoteHost -RemoteUrl 'git@gitlab.example.com:repo.git' | Should -Be 'gitlab.example.com'
    }

    It 'extracts host from ssh:// and https:// forms' {
        Get-GitRemoteHost -RemoteUrl 'ssh://git@gitlab.example.com/group/repo.git' | Should -Be 'gitlab.example.com'
        Get-GitRemoteHost -RemoteUrl 'https://gitlab.example.com/group/repo.git' | Should -Be 'gitlab.example.com'
    }

    It 'strips the port from host:port forms' {
        Get-GitRemoteHost -RemoteUrl 'http://192.168.27.159:18080/group/repo.git' | Should -Be '192.168.27.159'
    }

    It 'lowercases the host' {
        Get-GitRemoteHost -RemoteUrl 'git@GitLab.Example.COM:group/repo.git' | Should -Be 'gitlab.example.com'
    }

    It 'returns null for empty input' {
        Get-GitRemoteHost -RemoteUrl '' | Should -BeNullOrEmpty
        Get-GitRemoteHost -RemoteUrl $null | Should -BeNullOrEmpty
    }
}

Describe 'Get-GitIdentityIncludePattern' {
    It 'renders both scp variants because ** does not cross / right after a colon' {
        $patterns = Get-GitIdentityIncludePattern -GitHost 'gitlab.example.com'

        # 单级仓库路径走 :*，带分组的多级路径走 :*/**；只写 :** 会因为 ** 紧跟冒号退化成 * 而漏匹配。
        $patterns | Should -Contain 'git@gitlab.example.com:*'
        $patterns | Should -Contain 'git@gitlab.example.com:*/**'
    }

    It 'renders the ssh:// and https:// variants' {
        $patterns = Get-GitIdentityIncludePattern -GitHost 'gitlab.example.com'

        $patterns | Should -Contain 'ssh://git@gitlab.example.com/**'
        $patterns | Should -Contain 'https://gitlab.example.com/**'
    }

    It 'renders exactly four patterns per host' {
        (Get-GitIdentityIncludePattern -GitHost 'gitlab.example.com').Count | Should -Be 4
    }
}

Describe 'Get-GitIdentityConfig' {
    It 'loads profiles and normalizes hosts to lowercase' {
        $configPath = New-TestConfigFile -Path (Join-Path $TestDrive 'ok.json')
        $config = Get-GitIdentityConfig -ConfigPath $configPath

        $config.Profiles['company'].Email | Should -Be 'company@example.com'
        $config.Profiles['company'].Hosts | Should -Contain 'git.example.com'
        $config.Default | Should -Be 'personal'
    }

    It 'treats a profile without hosts as manual-only' {
        $configPath = New-TestConfigFile -Path (Join-Path $TestDrive 'no-hosts.json')
        $config = Get-GitIdentityConfig -ConfigPath $configPath

        $config.Profiles['personal'].Hosts.Count | Should -Be 0
    }

    It 'lets the config file override the built-in default source' {
        $configPath = New-TestConfigFile -Path (Join-Path $TestDrive 'override-default.json') -Overrides @{ default = 'company' }
        $config = Get-GitIdentityConfig -ConfigPath $configPath

        $config.Default | Should -Be 'company'
    }

    It 'throws with a self-service hint when the config file is missing' {
        { Get-GitIdentityConfig -ConfigPath (Join-Path $TestDrive 'missing.json') } | Should -Throw '*gitconfig.local.example.json*'
    }

    It 'throws when a profile lacks name or email' {
        $configPath = Join-Path $TestDrive 'bad-profile.json'
        @{ profiles = @{ broken = @{ name = 'only-name' } }; default = 'broken' } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8

        { Get-GitIdentityConfig -ConfigPath $configPath } | Should -Throw '*缺少 name 或 email*'
    }

    It 'throws when the default profile is not defined' {
        $configPath = New-TestConfigFile -Path (Join-Path $TestDrive 'bad-default.json') -Overrides @{ default = 'nope' }

        { Get-GitIdentityConfig -ConfigPath $configPath } | Should -Throw '*未在配置中定义*'
    }
}

Describe 'Resolve-GitIdentityProfileName' {
    BeforeAll {
        $script:Config = Get-GitIdentityConfig -ConfigPath (New-TestConfigFile -Path (Join-Path $TestDrive 'resolve.json'))
    }

    It 'matches a configured host regardless of URL form' {
        foreach ($url in @(
                'git@git.example.com:group/repo.git'
                'git@git.example.com:repo.git'
                'ssh://git@git.example.com/group/repo.git'
                'https://git.example.com/group/repo.git'
            )) {
            Resolve-GitIdentityProfileName -RemoteUrl $url -Config $script:Config | Should -Be 'company'
        }
    }

    It 'falls back to the default profile for unlisted hosts' {
        Resolve-GitIdentityProfileName -RemoteUrl 'git@github.com:user/repo.git' -Config $script:Config | Should -Be 'personal'
    }

    It 'falls back to the default profile when there is no remote' {
        Resolve-GitIdentityProfileName -RemoteUrl $null -Config $script:Config | Should -Be 'personal'
    }
}

Describe 'Get-GitIdentityStatus' {
    BeforeAll {
        $script:Config = Get-GitIdentityConfig -ConfigPath (New-TestConfigFile -Path (Join-Path $TestDrive 'status.json'))
    }

    It 'reports OK when the rule supplies the expected identity' {
        $status = Get-GitIdentityStatus -Identity (New-TestIdentity) -Config $script:Config

        $status.Status | Should -Be 'OK'
        $status.ExpectedProfile | Should -Be 'company'
    }

    It 'reports LocalOverride when the value is right but comes from the repo config' {
        $status = Get-GitIdentityStatus -Identity (New-TestIdentity -HasLocalOverride) -Config $script:Config

        # 值正确不代表健康：靠仓库级覆盖顶着的仓库换台机器 clone 就会用错身份。
        $status.Status | Should -Be 'LocalOverride'
    }

    It 'reports RuleGap when an override holds an identity the rules do not cover' {
        $identity = New-TestIdentity -Email 'company@example.com' -RemoteUrl 'http://192.168.27.159:18080/group/repo.git' -HasLocalOverride
        $status = Get-GitIdentityStatus -Identity $identity -Config $script:Config

        $status.Status | Should -Be 'RuleGap'
        $status.ExpectedProfile | Should -Be 'personal'
    }

    It 'reports Mismatch when the effective identity is simply wrong' {
        $identity = New-TestIdentity -Name 'personal-user' -Email 'personal@example.com'
        $status = Get-GitIdentityStatus -Identity $identity -Config $script:Config

        $status.Status | Should -Be 'Mismatch'
        $status.Detail | Should -BeLike '*company@example.com*'
    }

    It 'reports NoIdentity when user.email is unset' {
        $identity = New-TestIdentity -Email '' -Name ''
        $status = Get-GitIdentityStatus -Identity $identity -Config $script:Config

        $status.Status | Should -Be 'NoIdentity'
    }
}

Describe 'Test-GitIdentityRuleInstalled' -Skip:(-not $script:HasGit) {
    BeforeAll {
        $script:Config = Get-GitIdentityConfig -ConfigPath (New-TestConfigFile -Path (Join-Path $TestDrive 'rules.json'))
    }

    It 'reports every pattern as missing when nothing is installed' {
        $state = Test-GitIdentityRuleInstalled -Config $script:Config -GitConfigPath (Join-Path $TestDrive 'empty-gitconfig')

        $state.Expected.Count | Should -Be 4
        $state.Missing.Count | Should -Be 4
    }

    It 'reports nothing missing after the rules are installed' {
        $gitConfigPath = Join-Path $TestDrive 'installed-gitconfig'
        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath | Out-Null

        $state = Test-GitIdentityRuleInstalled -Config $script:Config -GitConfigPath $gitConfigPath
        $state.Missing.Count | Should -Be 0
    }
}

Describe 'Install-GitIdentityRule' -Skip:(-not $script:HasGit) {
    BeforeAll {
        $script:Config = Get-GitIdentityConfig -ConfigPath (New-TestConfigFile -Path (Join-Path $TestDrive 'install.json'))
    }

    It 'skips profiles without hosts' {
        $gitConfigPath = Join-Path $TestDrive 'skip-gitconfig'
        $rules = Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath

        @($rules | Where-Object { $_.Profile -eq 'personal' }).Count | Should -Be 0
        @($rules | Where-Object { $_.Profile -eq 'company' }).Count | Should -Be 4
    }

    It 'is idempotent across repeated installs' {
        $gitConfigPath = Join-Path $TestDrive 'idempotent-gitconfig'
        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath | Out-Null
        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath | Out-Null

        $keys = & git config -f $gitConfigPath --name-only --get-regexp '^includeif\.'
        @($keys).Count | Should -Be 4
    }

    It 'backs up an existing gitconfig before writing' {
        $gitConfigPath = Join-Path $TestDrive 'backup-gitconfig'
        Set-Content -LiteralPath $gitConfigPath -Value "[user]`n`tname = existing" -Encoding utf8

        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath | Out-Null

        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'backup-gitconfig.*.bak').Count | Should -BeGreaterThan 0
    }

    It 'preserves unrelated sections already present in the file' {
        $gitConfigPath = Join-Path $TestDrive 'preserve-gitconfig'
        Set-Content -LiteralPath $gitConfigPath -Value "[user]`n`tname = existing`n[credential]`n`thelper = manager" -Encoding utf8

        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath | Out-Null

        (& git config -f $gitConfigPath --get user.name) | Should -Be 'existing'
        (& git config -f $gitConfigPath --get credential.helper) | Should -Be 'manager'
    }

    It 'writes nothing under -WhatIf' {
        $gitConfigPath = Join-Path $TestDrive 'whatif-gitconfig'

        Install-GitIdentityRule -Config $script:Config -GitConfigPath $gitConfigPath -WhatIf | Out-Null

        Test-Path -LiteralPath $gitConfigPath | Should -BeFalse
    }
}

Describe 'Get-GitIdentityAudit' -Skip:(-not $script:HasGit) {
    BeforeAll {
        $script:Config = Get-GitIdentityConfig -ConfigPath (New-TestConfigFile -Path (Join-Path $TestDrive 'audit.json'))

        function New-TestRepository {
            param(
                [Parameter(Mandatory)]
                [string]$Path,

                [string]$RemoteUrl,

                [string]$LocalName,

                [string]$LocalEmail
            )

            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            & git -C $Path init -q
            if (-not [string]::IsNullOrWhiteSpace($RemoteUrl)) {
                & git -C $Path remote add origin $RemoteUrl
            }
            if (-not [string]::IsNullOrWhiteSpace($LocalEmail)) {
                & git -C $Path config user.name $LocalName
                & git -C $Path config user.email $LocalEmail
            }

            return $Path
        }
    }

    It 'flags a repo whose correct identity comes from a local override' {
        $repo = New-TestRepository -Path (Join-Path $TestDrive 'repo-override') `
            -RemoteUrl 'git@git.example.com:group/repo.git' `
            -LocalName 'company-user' -LocalEmail 'company@example.com'

        $audit = Get-GitIdentityAudit -Path $repo -Config $script:Config

        $audit.Count | Should -Be 1
        $audit[0].Expected | Should -Be 'company'
        $audit[0].Status | Should -Be 'LocalOverride'
    }

    It 'flags a repo pinned to the wrong identity' {
        $repo = New-TestRepository -Path (Join-Path $TestDrive 'repo-mismatch') `
            -RemoteUrl 'git@git.example.com:group/repo.git' `
            -LocalName 'personal-user' -LocalEmail 'personal@example.com'

        $audit = Get-GitIdentityAudit -Path $repo -Config $script:Config

        # 期望 company 却钉着 personal：值不对且来自覆盖，属于规则没覆盖到的缺口。
        $audit[0].Status | Should -Be 'RuleGap'
    }

    It 'records the origin file of the effective identity' {
        $repo = New-TestRepository -Path (Join-Path $TestDrive 'repo-origin') `
            -RemoteUrl 'git@git.example.com:group/repo.git' `
            -LocalName 'company-user' -LocalEmail 'company@example.com'

        $audit = Get-GitIdentityAudit -Path $repo -Config $script:Config

        $audit[0].OriginFile | Should -Be 'config'
    }
}

Describe 'Clear-GitIdentityLocalOverride' -Skip:(-not $script:HasGit) {
    It 'removes the repo-level user section and leaves other config intact' {
        $repo = Join-Path $TestDrive 'repo-clear'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.name 'company-user'
        & git -C $repo config user.email 'company@example.com'
        & git -C $repo config core.ignorecase false

        Clear-GitIdentityLocalOverride -RepositoryPath $repo | Should -BeTrue

        (& git -C $repo config --local --get user.email) | Should -BeNullOrEmpty
        (& git -C $repo config --local --get core.ignorecase) | Should -Be 'false'
    }

    It 'writes nothing under -WhatIf' {
        $repo = Join-Path $TestDrive 'repo-clear-whatif'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 'company@example.com'

        Clear-GitIdentityLocalOverride -RepositoryPath $repo -WhatIf | Out-Null

        (& git -C $repo config --local --get user.email) | Should -Be 'company@example.com'
    }
}
