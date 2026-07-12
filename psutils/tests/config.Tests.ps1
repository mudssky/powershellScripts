BeforeAll {
    $script:ConfigModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\config.psm1'))
    $script:ConfigSourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\config'))
    Import-Module $script:ConfigModulePath -Force
}

Describe 'Resolve-ConfigSources' {
    It 'auto-discovers .env and .env.local and records the winning source' {
        $basePath = Join-Path $TestDrive 'auto-discover'
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null
        Set-Content -Path (Join-Path $basePath '.env') -Value @'
DEFAULT_USER=from-env
DEFAULT_PASSWORD=from-env
'@
        Set-Content -Path (Join-Path $basePath '.env.local') -Value @'
DEFAULT_USER=from-env-local
'@

        $result = Resolve-ConfigSources -BasePath $basePath -IncludeTrace

        $result.Values.DEFAULT_USER | Should -Be 'from-env-local'
        $result.Values.DEFAULT_PASSWORD | Should -Be 'from-env'
        $result.Sources.DEFAULT_USER | Should -Be '.env.local'
        $result.Trace.DEFAULT_USER.Candidates.Count | Should -Be 2
    }

    It 'throws on invalid dotenv lines instead of silently ignoring them' {
        $basePath = Join-Path $TestDrive 'invalid-env'
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null
        Set-Content -Path (Join-Path $basePath '.env') -Value @'
GOOD_KEY=value
this is not valid
'@

        { Resolve-ConfigSources -ConfigFile (Join-Path $basePath '.env') } | Should -Throw '无效 env 行'
    }

    It 'accepts explicit -ConfigFile input for env and json files' {
        $basePath = Join-Path $TestDrive 'config-files'
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null
        Set-Content -Path (Join-Path $basePath '.env') -Value 'DEFAULT_USER=from-env'
        Set-Content -Path (Join-Path $basePath 'config.json') -Value @'
{
  "DEFAULT_USER": "from-json",
  "COMPOSE_PROJECT_NAME": "demo-project"
}
'@

        $result = Resolve-ConfigSources -ConfigFile (Join-Path $basePath '.env'), (Join-Path $basePath 'config.json')

        $result.Values.DEFAULT_USER | Should -Be 'from-json'
        $result.Values.COMPOSE_PROJECT_NAME | Should -Be 'demo-project'
        $result.Sources.COMPOSE_PROJECT_NAME | Should -Be 'config.json'
    }

    It 'supports explicit structured sources for script callers' {
        $result = Resolve-ConfigSources -Sources @(
            @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ DEFAULT_USER = 'postgres'; DEFAULT_PASSWORD = '12345678' } }
            @{ Type = 'Hashtable'; Name = 'CliEnv'; Data = @{ DEFAULT_USER = 'cli-user' } }
        )

        $result.Values.DEFAULT_USER | Should -Be 'cli-user'
        $result.Values.DEFAULT_PASSWORD | Should -Be '12345678'
        $result.Sources.DEFAULT_USER | Should -Be 'CliEnv'
    }

    It 'resolves home-relative paths in explicit structured file sources' {
        $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $configPath = Join-Path $userHome '.config/project-launcher/config-source-test.local.json'
        $configDirectory = Split-Path -Parent $configPath
        New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
        Set-Content -Path $configPath -Encoding utf8NoBOM -Value @'
{
  "PROJECT_LAUNCHER_TEST": "from-user-config"
}
'@

        try {
            $result = Resolve-ConfigSources -Sources @(
                @{ Type = 'JsonFile'; Name = 'UserConfig'; Path = '~/.config\project-launcher\config-source-test.local.json' }
            ) -BasePath $TestDrive -ErrorOnMissing
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        }

        $result.Values.PROJECT_LAUNCHER_TEST | Should -Be 'from-user-config'
        $result.Sources.PROJECT_LAUNCHER_TEST | Should -Be 'UserConfig'
    }
}

Describe 'Resolve-DefaultEnvFiles' {
    BeforeAll {
        . (Join-Path $script:ConfigSourceRoot 'discovery.ps1')
    }

    It 'prefers the primary base path when it contains any default env file' {
        $primaryBase = Join-Path $TestDrive 'primary'
        $fallbackBase = Join-Path $TestDrive 'fallback'
        New-Item -ItemType Directory -Path $primaryBase -Force | Out-Null
        New-Item -ItemType Directory -Path $fallbackBase -Force | Out-Null
        Set-Content -Path (Join-Path $primaryBase '.env') -Value 'PRIMARY_KEY=1'
        Set-Content -Path (Join-Path $fallbackBase '.env.local') -Value 'FALLBACK_KEY=1'

        $result = Resolve-DefaultEnvFiles -PrimaryBasePath $primaryBase -FallbackBasePath $fallbackBase

        $result.BasePath | Should -Be $primaryBase
        $result.Paths | Should -HaveCount 1
        $result.Paths[0] | Should -Be (Join-Path $primaryBase '.env')
    }

    It 'falls back only when the primary base path has no default env file at all' {
        $primaryBase = Join-Path $TestDrive 'empty'
        $fallbackBase = Join-Path $TestDrive 'fallback-only'
        New-Item -ItemType Directory -Path $primaryBase -Force | Out-Null
        New-Item -ItemType Directory -Path $fallbackBase -Force | Out-Null
        Set-Content -Path (Join-Path $fallbackBase '.env') -Value 'FALLBACK_KEY=1'
        Set-Content -Path (Join-Path $fallbackBase '.env.local') -Value 'FALLBACK_OVERRIDE=1'

        $result = Resolve-DefaultEnvFiles -PrimaryBasePath $primaryBase -FallbackBasePath $fallbackBase

        $result.BasePath | Should -Be $fallbackBase
        $result.Paths | Should -HaveCount 2
        $result.Paths[0] | Should -Be (Join-Path $fallbackBase '.env')
        $result.Paths[1] | Should -Be (Join-Path $fallbackBase '.env.local')
    }
}

Describe 'Config object helpers' {
    It '将 IDictionary 转换为普通 hashtable' {
        $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
        $dictionary['Name'] = 'agent-browser'
        $dictionary['Enabled'] = $true

        $result = ConvertTo-ConfigHashtable -InputObject $dictionary

        $result | Should -BeOfType hashtable
        $result.Name | Should -Be 'agent-browser'
        $result.Enabled | Should -BeTrue
    }

    It '按大小写不敏感方式读取配置值并保留原始类型' {
        $values = @{
            RetryCount = 3
            Agents     = @('claude', 'codex')
        }

        $retryCount = Get-ConfigValue -Values $values -Name 'retrycount'
        $agents = Get-ConfigValue -Values $values -Name 'AGENTS'

        $retryCount | Should -Be 3
        $retryCount | Should -BeOfType int
        $agents | Should -Be @('claude', 'codex')
    }

    It '未命中配置键时返回默认值' {
        $result = Get-ConfigValue -Values @{ Name = 'ctx7' } -Name 'missing' -DefaultValue 'fallback'

        $result | Should -Be 'fallback'
    }

    It '按平台优先级读取映射值' {
        $platform = [pscustomobject]@{
            OperatingSystem = 'linux'
            Architecture    = 'x64'
            Key             = 'linux-x64'
        }

        $result = Resolve-ConfigPlatformValue -Value @{
            default     = 'generic'
            linux       = 'linux-any'
            'linux-x64' = 'linux-x64-value'
        } -Platform $platform -Label 'asset_patterns'

        $result | Should -Be 'linux-x64-value'
    }

    It '允许调用方显式接受标量平台值' {
        $platform = [pscustomobject]@{
            OperatingSystem = 'linux'
            Architecture    = 'x64'
            Key             = 'linux-x64'
        }

        $result = Resolve-ConfigPlatformValue -Value 'tool' -Platform $platform -Label 'executables' -AllowScalar

        $result | Should -Be 'tool'
    }

    It '默认拒绝标量平台映射值' {
        $platform = [pscustomobject]@{
            OperatingSystem = 'linux'
            Architecture    = 'x64'
            Key             = 'linux-x64'
        }

        { Resolve-ConfigPlatformValue -Value 'tool' -Platform $platform -Label 'executables' } |
            Should -Throw 'executables 需要按平台配置*'
    }
}

Describe 'Config path helpers' {
    AfterEach {
        Remove-Item Env:\CONFIG_PATH_TEST_ROOT -ErrorAction SilentlyContinue
    }

    It '展开 ${VAR} 环境变量占位符' {
        $env:CONFIG_PATH_TEST_ROOT = Join-Path $TestDrive 'env-root'

        $result = Resolve-ConfigEnvPlaceholder -Value '${CONFIG_PATH_TEST_ROOT}/skills' -Context 'test.path'

        [System.IO.Path]::GetFullPath($result) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $env:CONFIG_PATH_TEST_ROOT 'skills')))
    }

    It '缺失 ${VAR} 时抛出包含上下文的错误' {
        { Resolve-ConfigEnvPlaceholder -Value '${CONFIG_PATH_TEST_MISSING}/skills' -Context 'tool.path' } |
            Should -Throw '环境变量未设置: CONFIG_PATH_TEST_MISSING（tool.path）'
    }

    It '相对路径按 BasePath 解析为绝对路径' {
        $basePath = Join-Path $TestDrive 'config-root'

        $result = Resolve-ConfigPath -Path './dev/my-skill' -BasePath $basePath -Context 'skill.source'

        $result | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $basePath './dev/my-skill')))
    }

    It '支持用户主目录 ~ 路径' {
        $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

        $result = Resolve-ConfigPath -Path '~/skills' -BasePath $TestDrive -Context 'tool.path'

        $result | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $userHome 'skills')))
    }

    It '支持混合分隔符的用户主目录 ~ 路径' {
        $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

        $result = Resolve-ConfigPath -Path '~/.config\project-launcher\project-launcher.local.json' -BasePath $TestDrive -Context 'tool.path'

        $result | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $userHome '.config/project-launcher/project-launcher.local.json')))
    }

    It '空白路径会抛出明确错误' {
        { Resolve-ConfigPath -Path '   ' -BasePath $TestDrive -Context 'projectPath' } |
            Should -Throw '路径配置不能为空: projectPath'
    }
}

Describe 'Invoke-WithScopedEnvironment' {
    AfterEach {
        Remove-Item Env:\CONFIG_TEST_NEW -ErrorAction SilentlyContinue
        Remove-Item Env:\CONFIG_TEST_EXISTING -ErrorAction SilentlyContinue
    }

    It 'restores overwritten values and removes newly-added values on success' {
        $env:CONFIG_TEST_EXISTING = 'before'

        $result = Invoke-WithScopedEnvironment -Variables @{
            CONFIG_TEST_EXISTING = 'inside'
            CONFIG_TEST_NEW      = 'created'
        } -ScriptBlock {
            [pscustomobject]@{
                Existing = $env:CONFIG_TEST_EXISTING
                NewValue = $env:CONFIG_TEST_NEW
            }
        }

        $result.Existing | Should -Be 'inside'
        $result.NewValue | Should -Be 'created'
        $env:CONFIG_TEST_EXISTING | Should -Be 'before'
        Test-Path Env:\CONFIG_TEST_NEW | Should -Be $false
    }

    It 'restores values after an exception and rethrows the error' {
        $env:CONFIG_TEST_EXISTING = 'before'

        {
            Invoke-WithScopedEnvironment -Variables @{ CONFIG_TEST_EXISTING = 'inside' } -ScriptBlock {
                throw 'boom'
            }
        } | Should -Throw 'boom'

        $env:CONFIG_TEST_EXISTING | Should -Be 'before'
    }
}

Describe 'Extended config source types' {
    It 'reads PowerShell data files as configuration values' {
        $dataFile = Join-Path $TestDrive 'tool.psd1'
        Set-Content -Path $dataFile -Encoding utf8NoBOM -Value @'
@{
    BinName = 'Invoke-AiAgent.ps1'
    Entry   = 'main.ps1'
}
'@

        $result = Resolve-ConfigSources -Sources @(
            @{ Type = 'PowerShellDataFile'; Name = 'ToolManifest'; Path = $dataFile }
        ) -ErrorOnMissing

        $result.Values.BinName | Should -Be 'Invoke-AiAgent.ps1'
        $result.Values.Entry | Should -Be 'main.ps1'
        $result.Sources.BinName | Should -Be 'ToolManifest'
    }

    It 'reads Markdown frontmatter metadata and preserves content' {
        $promptFile = Join-Path $TestDrive 'commit.md'
        Set-Content -Path $promptFile -Encoding utf8NoBOM -Value @'
---
agent: codex
reasoning_effort: medium
json: false
budget: 3
---

提交当前 Git 变更。
'@

        $result = Resolve-ConfigSources -Sources @(
            @{ Type = 'MarkdownFrontMatter'; Name = 'PromptPreset'; Path = $promptFile }
        ) -ErrorOnMissing

        $result.Values.agent | Should -Be 'codex'
        $result.Values.reasoning_effort | Should -Be 'medium'
        $result.Values.json | Should -BeFalse
        $result.Values.budget | Should -Be 3
        $result.Values.__content.Trim() | Should -Be '提交当前 Git 变更。'
    }

    It 'reports Markdown frontmatter parse errors with path and line number' {
        $promptFile = Join-Path $TestDrive 'bad.md'
        Set-Content -Path $promptFile -Encoding utf8NoBOM -Value @'
---
agent codex
---
body
'@

        { Resolve-ConfigSources -Sources @(
                @{ Type = 'MarkdownFrontMatter'; Name = 'PromptPreset'; Path = $promptFile }
            ) -ErrorOnMissing } | Should -Throw "*${promptFile}:2*"
    }

    It 'converts CLI parameters into snake_case config keys and skips empty values' {
        $result = Resolve-ConfigSources -Sources @(
            @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ agent = 'codex'; reasoning_effort = 'medium' } }
            @{ Type = 'CliParameters'; Name = 'Cli'; Data = @{
                    Agent           = 'claude'
                    ReasoningEffort = 'high'
                    Model           = ''
                    RawArguments    = @('ignored')
                }; ExcludeKeys = @('RawArguments') }
        )

        $result.Values.agent | Should -Be 'claude'
        $result.Values.reasoning_effort | Should -Be 'high'
        $result.Values.ContainsKey('model') | Should -BeFalse
        $result.Values.ContainsKey('raw_arguments') | Should -BeFalse
    }

    It 'merges defaults, frontmatter and CLI sources by declaration order' {
        $promptFile = Join-Path $TestDrive 'commit.md'
        Set-Content -Path $promptFile -Encoding utf8NoBOM -Value @'
---
agent: codex
reasoning_effort: medium
---
body
'@

        $result = Resolve-ConfigSources -Sources @(
            @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ agent = 'codex'; reasoning_effort = 'low'; work_dir = '/repo' } }
            @{ Type = 'MarkdownFrontMatter'; Name = 'Preset'; Path = $promptFile }
            @{ Type = 'CliParameters'; Name = 'Cli'; Data = @{ ReasoningEffort = 'high' } }
        )

        $result.Values.agent | Should -Be 'codex'
        $result.Values.reasoning_effort | Should -Be 'high'
        $result.Values.work_dir | Should -Be '/repo'
        $result.Values.__content.Trim() | Should -Be 'body'
        $result.Sources.reasoning_effort | Should -Be 'Cli'
    }
}

Describe 'Read-ConfigSshClientConfig' {
    It 'parses launchable Host blocks and common connection fields' {
        $configPath = Join-Path $TestDrive 'ssh_config'
        Set-Content -Path $configPath -Encoding utf8NoBOM -Value @'
Host proj-srm-trellis
  HostName 192.168.27.77
  User administrator
  Port 32222
  RequestTTY yes
  RemoteCommand cd ~/projects/work/hubs/srm-trellis && exec zellij attach -c srm-trellis

Host internal-server
  HostName example.internal # trailing comment
  User deploy
'@

        $blocks = @(Read-ConfigSshClientConfig -Path $configPath)

        $blocks | Should -HaveCount 2
        $blocks[0].Host | Should -Be 'proj-srm-trellis'
        $blocks[0].HostName | Should -Be '192.168.27.77'
        $blocks[0].User | Should -Be 'administrator'
        $blocks[0].Port | Should -Be '32222'
        $blocks[0].RequestTTY | Should -Be 'yes'
        $blocks[0].RemoteCommand | Should -Be 'cd ~/projects/work/hubs/srm-trellis && exec zellij attach -c srm-trellis'
        $blocks[0].IsLaunchCandidate | Should -BeTrue
        $blocks[1].HostName | Should -Be 'example.internal'
    }

    It 'marks multi-pattern and wildcard Host blocks as non-launchable' {
        $configPath = Join-Path $TestDrive 'ssh_config_patterns'
        Set-Content -Path $configPath -Encoding utf8NoBOM -Value @'
Host *
  User fallback

Host proj-* !proj-old
  User ignored

Host good-host
  HostName good.example
'@

        $blocks = @(Read-ConfigSshClientConfig -Path $configPath)

        $blocks | Should -HaveCount 3
        $blocks[0].Host | Should -Be '*'
        $blocks[0].IsLaunchCandidate | Should -BeFalse
        $blocks[1].HostPatterns | Should -Be @('proj-*', '!proj-old')
        $blocks[1].IsLaunchCandidate | Should -BeFalse
        $blocks[2].Host | Should -Be 'good-host'
        $blocks[2].IsLaunchCandidate | Should -BeTrue
    }

    It 'supports equals syntax and stops collecting when a Match block starts' {
        $configPath = Join-Path $TestDrive 'ssh_config_match'
        Set-Content -Path $configPath -Encoding utf8NoBOM -Value @'
Host equals-host
  HostName=equals.example
  User=deploy
Match host *
  RemoteCommand should-not-attach
'@

        $blocks = @(Read-ConfigSshClientConfig -Path $configPath)

        $blocks | Should -HaveCount 1
        $blocks[0].HostName | Should -Be 'equals.example'
        $blocks[0].User | Should -Be 'deploy'
        $blocks[0].RemoteCommand | Should -BeNullOrEmpty
    }

    It 'exports the shared config readers from both config module and psutils manifest' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..' 'psutils.psd1')

        Get-Command Read-ConfigEnvFile -Module config | Should -Not -BeNullOrEmpty
        Get-Command Resolve-DefaultEnvFiles -Module config | Should -Not -BeNullOrEmpty
        @($manifest.FunctionsToExport) | Should -Contain 'Read-ConfigEnvFile'
        @($manifest.FunctionsToExport) | Should -Contain 'Resolve-DefaultEnvFiles'
        @($manifest.FunctionsToExport) | Should -Contain 'Read-ConfigSshClientConfig'
    }
}
