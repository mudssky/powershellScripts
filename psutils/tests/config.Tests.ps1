BeforeAll {
    $script:ConfigModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\config.psm1'))
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
