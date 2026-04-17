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
