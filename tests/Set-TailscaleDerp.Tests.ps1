Set-StrictMode -Version Latest

BeforeAll {
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

Describe 'Get-TailscaleDerpManagedPaths' {
    It 'builds a Linux/macOS config path under the user home directory' {
        $paths = Get-TailscaleDerpManagedPaths -Platform 'Linux' -HomeDirectory '/home/demo'

        $paths.DerpJsonPath | Should -Be '/home/demo/.config/powershell-scripts/tailscale/derp.json'
        $paths.StatePath | Should -Be '/home/demo/.config/powershell-scripts/tailscale/derp-state.json'
    }

    It 'builds a Windows config path under APPDATA' {
        $paths = Get-TailscaleDerpManagedPaths -Platform 'Windows' -AppDataDirectory 'C:\Users\Demo\AppData\Roaming'

        $paths.DerpJsonPath | Should -Be 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp.json'
        $paths.StatePath | Should -Be 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp-state.json'
    }
}

Describe 'Convert-TailscalePathToFileUri' {
    It 'converts a Windows path to a file URI' {
        Convert-TailscalePathToFileUri -Path 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp.json' |
            Should -Be 'file:///C:/Users/Demo/AppData/Roaming/powershell-scripts/tailscale/derp.json'
    }

    It 'converts a POSIX path to a file URI' {
        Convert-TailscalePathToFileUri -Path '/home/demo/.config/powershell-scripts/tailscale/derp.json' |
            Should -Be 'file:///home/demo/.config/powershell-scripts/tailscale/derp.json'
    }
}

Describe 'New-TailscaleDerpMapJson' {
    It 'builds the expected single-region DERP map document' {
        $json = New-TailscaleDerpMapJson `
            -ServerIp '203.0.113.10' `
            -RegionId 900 `
            -RegionCode 'cn-custom' `
            -NodeName 'cn-node' `
            -DerpPort 8443 `
            -StunPort 3478

        $doc = $json | ConvertFrom-Json -Depth 10
        $node = $doc.Regions.PSObject.Properties['900'].Value.Nodes[0]

        $node.HostName | Should -Be '203.0.113.10'
        $node.DERPPort | Should -Be 8443
        $node.STUNPort | Should -Be 3478
        $node.InsecureForTests | Should -BeTrue
    }
}
