Set-StrictMode -Version Latest

BeforeAll {
    # 通过测试专用跳过开关加载脚本函数，避免 dot-source 时直接执行 docker compose 或 LiteLLM API 同步。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:StartScriptPath = Join-Path $script:RepoRoot 'ai/gateway/litellm/start.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_LITELLM_START_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_LITELLM_START_MAIN = '1'

    . $script:StartScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_LITELLM_START_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_LITELLM_START_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'LiteLLM start usage' {
    It 'documents the sync-models action' {
        $usage = Show-Usage

        $usage | Should -Match '\[up\|apply\|down\|restart\|logs\|ps\|pull\|sync-models\]'
        $usage | Should -Match '\./start\.ps1 apply'
        $usage | Should -Match '\./start\.ps1 sync-models'
    }
}

Describe 'Get-LiteLLMComposeActionArgs' {
    It 'builds apply args that recreate the LiteLLM service so YAML config is reloaded' {
        $args = Get-LiteLLMComposeActionArgs `
            -Action 'apply' `
            -BaseArgs @('compose', '-f', 'compose.yaml') `
            -ExtraArgs @('--wait')

        $args | Should -Be @('compose', '-f', 'compose.yaml', 'up', '-d', '--force-recreate', '--wait', 'litellm')
    }
}

Describe 'Read-LiteLLMEnvFile' {
    It 'loads simple KEY=value pairs and ignores comments' {
        $envPath = Join-Path $TestDrive '.env.local'
        @(
            '# comment'
            'LITELLM_MASTER_KEY=sk-test'
            'LITELLM_HOST_PORT=34001'
            'EMPTY_VALUE='
        ) | Set-Content -LiteralPath $envPath

        $values = Read-LiteLLMEnvFile -Path $envPath

        $values.LITELLM_MASTER_KEY | Should -Be 'sk-test'
        $values.LITELLM_HOST_PORT | Should -Be '34001'
        $values.EMPTY_VALUE | Should -Be ''
        $values.ContainsKey('# comment') | Should -BeFalse
    }
}

Describe 'ConvertFrom-LiteLLMConfigJson' {
    It 'returns store_model_in_db and managed models from container config json' {
        $json = @'
{"store_model_in_db":false,"model_list":[{"model_name":"gpt-5.5","litellm_params":{"model":"openai/gpt-5.5"}}]}
'@

        $config = ConvertFrom-LiteLLMConfigJson -Json $json

        $config.StoreModelInDb | Should -BeFalse
        $config.Models.Count | Should -Be 1
        $config.Models[0].model_info.litellm_sync_managed | Should -BeTrue
    }
}

Describe 'Get-LiteLLMModelSyncPlan' {
    It 'creates missing models and deletes stale config-managed models' {
        $configuredModels = @(
            [pscustomobject]@{
                model_name     = 'gpt-5.5'
                litellm_params = [ordered]@{ model = 'openai/gpt-5.5' }
            },
            [pscustomobject]@{
                model_name     = '*'
                litellm_params = [ordered]@{ model = 'openai/*' }
            }
        )
        $currentModels = @(
            [pscustomobject]@{
                model_name     = 'gpt-5.4'
                litellm_params = [ordered]@{ model = 'openai/gpt-5.4' }
                model_info     = [pscustomobject]@{ id = 'old-gpt'; db_model = $true; litellm_sync_managed = $true }
            },
            [pscustomobject]@{
                model_name     = '*'
                litellm_params = [ordered]@{ model = 'openai/*' }
                model_info     = [pscustomobject]@{ id = 'wildcard'; db_model = $true; litellm_sync_managed = $true }
            },
            [pscustomobject]@{
                model_name     = 'manual-only'
                litellm_params = [ordered]@{ model = 'openai/manual-only' }
                model_info     = [pscustomobject]@{ id = 'manual'; db_model = $true }
            }
        )

        $plan = Get-LiteLLMModelSyncPlan -ConfiguredModels $configuredModels -CurrentModels $currentModels

        $plan.Create.model_name | Should -Be @('gpt-5.5')
        $plan.Delete.id | Should -Be @('old-gpt')
        $plan.Keep.model_name | Should -Be @('*', 'manual-only')
    }

    It 'does not recreate a model when a matching managed database model already exists beside yaml models' {
        $configuredModels = @(
            [pscustomobject]@{
                model_name     = 'gpt-5.5'
                litellm_params = [ordered]@{ model = 'openai/gpt-5.5' }
            }
        )
        $currentModels = @(
            [pscustomobject]@{
                model_name     = 'gpt-5.5'
                litellm_params = [ordered]@{ model = 'openai/gpt-5.5' }
                model_info     = [pscustomobject]@{ id = 'yaml-gpt'; db_model = $false }
            },
            [pscustomobject]@{
                model_name     = 'gpt-5.5'
                litellm_params = [ordered]@{ model = 'openai/gpt-5.5' }
                model_info     = [pscustomobject]@{ id = 'db-gpt'; db_model = $true; litellm_sync_managed = $true }
            }
        )

        $plan = Get-LiteLLMModelSyncPlan -ConfiguredModels $configuredModels -CurrentModels $currentModels

        $plan.Create.Count | Should -Be 0
        $plan.Delete.Count | Should -Be 0
        $plan.Keep.model_name | Should -Contain 'gpt-5.5'
    }
}
