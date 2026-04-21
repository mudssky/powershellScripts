Set-StrictMode -Version Latest

BeforeAll {
    # 通过环境变量跳过脚本文件底部的主入口，允许测试直接调用内部函数。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN = '1'

    . $script:ScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'Invoke-SetTailscaleDerpCommand - PrintSnippet' {
    It 'prints a single-region derpMap snippet without requiring PolicyPath' {
        $snippet = Invoke-SetTailscaleDerpCommand `
            -ServerIp '203.0.113.10' `
            -PrintSnippet

        $doc = $snippet | ConvertFrom-Json -AsHashtable -Depth 20
        $doc['derpMap']['Regions']['900']['Nodes'][0]['HostName'] | Should -Be '203.0.113.10'
        $doc['derpMap']['Regions']['900']['Nodes'][0]['DERPPort'] | Should -Be 8443
    }

    It 'rejects PrintSnippet combined with Reset' {
        {
            Invoke-SetTailscaleDerpCommand -ServerIp '203.0.113.10' -PrintSnippet -Reset
        } | Should -Throw '*Parameter set*'
    }
}

Describe 'Read-TailscalePolicyDocument' {
    It 'parses HuJSON comments and trailing commas without breaking URLs inside strings' {
        $policyPath = Join-Path $TestDrive 'tailnet-policy.hujson'
        @'
{
  // 现有 ACL 配置
  "acls": [],
  "hosts": {
    "control": "https://controlplane.tailscale.com",
  },
  /* 受管 Region 之外的配置必须保留 */
  "derpMap": {
    "Regions": {
      "901": {
        "RegionID": 901,
        "RegionCode": "keep-me",
        "Nodes": []
      },
    },
  },
}
'@ | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

        $document = Read-TailscalePolicyDocument -Path $policyPath

        $document['hosts']['control'] | Should -Be 'https://controlplane.tailscale.com'
        $document['derpMap']['Regions']['901']['RegionCode'] | Should -Be 'keep-me'
    }
}

Describe 'Set-TailscalePolicyDerpRegion' {
    It 'adds or replaces the managed Region while preserving other Regions' {
        $policy = [ordered]@{
            derpMap = [ordered]@{
                Regions = [ordered]@{
                    '901' = [ordered]@{
                        RegionID   = 901
                        RegionCode = 'keep-me'
                        Nodes      = @()
                    }
                }
            }
        }

        $region = New-TailscaleDerpRegion `
            -ServerIp '203.0.113.10' `
            -RegionId 900 `
            -RegionCode 'cn-custom' `
            -NodeName 'cn-node' `
            -DerpPort 8443 `
            -StunPort 3478

        $result = Set-TailscalePolicyDerpRegion -Policy $policy -Region $region

        $result.Policy['derpMap']['Regions']['901']['RegionCode'] | Should -Be 'keep-me'
        $result.Policy['derpMap']['Regions']['900']['Nodes'][0]['HostName'] | Should -Be '203.0.113.10'
        $result.Changed | Should -BeTrue
    }
}

Describe 'Invoke-SetTailscaleDerpCommand - CommandFlow' {
    It 'writes the managed Region to OutputPath and keeps PolicyPath unchanged' {
        $policyPath = Join-Path $TestDrive 'tailnet-policy.hujson'
        $outputPath = Join-Path $TestDrive 'tailnet-policy.generated.json'
        @'
{
  "groups": {},
  "derpMap": {
    "Regions": {
      "901": {
        "RegionID": 901,
        "RegionCode": "keep-me",
        "Nodes": []
      }
    }
  }
}
'@ | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

        $result = Invoke-SetTailscaleDerpCommand `
            -ServerIp '203.0.113.10' `
            -PolicyPath $policyPath `
            -OutputPath $outputPath `
            -PassThru

        $original = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
        $generated = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20

        $original['derpMap']['Regions'].Contains('900') | Should -BeFalse
        $generated['derpMap']['Regions']['900']['Nodes'][0]['HostName'] | Should -Be '203.0.113.10'
        $result.Mode | Should -Be 'Apply'
        $result.OutputPath | Should -Be $outputPath
        $result.Changed | Should -BeTrue
    }

    It 'removes the managed Region and drops derpMap when it becomes empty' {
        $policyPath = Join-Path $TestDrive 'tailnet-policy.hujson'
        @'
{
  "derpMap": {
    "Regions": {
      "900": {
        "RegionID": 900,
        "RegionCode": "cn-custom",
        "Nodes": []
      }
    }
  }
}
'@ | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

        $result = Invoke-SetTailscaleDerpCommand -Reset -PolicyPath $policyPath -PassThru
        $saved = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20

        $saved.Contains('derpMap') | Should -BeFalse
        $result.Mode | Should -Be 'Reset'
        $result.RemovedDerpMap | Should -BeTrue
    }

    It 'does not write files when WhatIf is enabled' {
        $policyPath = Join-Path $TestDrive 'tailnet-policy.hujson'
        '{"groups":{}}' | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM
        $before = Get-Content -LiteralPath $policyPath -Raw

        Invoke-SetTailscaleDerpCommand `
            -ServerIp '203.0.113.10' `
            -PolicyPath $policyPath `
            -WhatIf

        (Get-Content -LiteralPath $policyPath -Raw) | Should -Be $before
    }
}

Describe 'Invoke-SetTailscaleDerpCommand - Validation' {
    It 'fails when PolicyPath does not exist' {
        {
            Invoke-SetTailscaleDerpCommand `
                -ServerIp '203.0.113.10' `
                -PolicyPath (Join-Path $TestDrive 'missing.hujson')
        } | Should -Throw '*未找到 tailnet policy 文件*'
    }

    It 'fails when the policy document cannot be parsed' {
        $policyPath = Join-Path $TestDrive 'broken.hujson'
        '{ invalid json }' | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

        {
            Invoke-SetTailscaleDerpCommand -ServerIp '203.0.113.10' -PolicyPath $policyPath
        } | Should -Throw '*无法解析为 JSON/HuJSON*'
    }

    It 'fails when the top-level policy is not an object' {
        $policyPath = Join-Path $TestDrive 'array.hujson'
        '[1,2,3]' | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

        {
            Invoke-SetTailscaleDerpCommand -ServerIp '203.0.113.10' -PolicyPath $policyPath
        } | Should -Throw '*顶层必须是对象*'
    }

    It 'fails when ServerIp is blank or malformed' {
        {
            Invoke-SetTailscaleDerpCommand -ServerIp 'bad host!' -PrintSnippet
        } | Should -Throw '*无效的服务器地址*'
    }
}
