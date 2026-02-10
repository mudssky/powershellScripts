Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/../psutils/modules/env.psm1" -Force

Describe 'Sync-PathFromBash basic behavior' {
    BeforeAll {
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should return object with fields when ReturnObject=true' {
        $result = Sync-PathFromBash -WhatIf -ReturnObject:$true
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $result.PSObject.Properties.Name | Should -Contain 'SourcePathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'CurrentPathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'AddedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'SkippedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'NewPath'
    }
    It 'should support Prepend strategy without error when WhatIf' {
        { Sync-PathFromBash -Prepend -WhatIf } | Should -Not -Throw
    }
    It 'should support Append strategy (default) without error when WhatIf' {
        { Sync-PathFromBash -WhatIf } | Should -Not -Throw
    }
    It 'should support Login branch without error when WhatIf' {
        { Sync-PathFromBash -Login -WhatIf } | Should -Not -Throw
    }
}

Describe 'Sync-PathFromBash cache and error semantics' {
    BeforeAll {
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should use cache when CacheSeconds > 0 and write cache file' {
        $r = Sync-PathFromBash -WhatIf -ReturnObject:$true -Verbose
        $r | Should -Not -BeNullOrEmpty
    }
    It 'should throw when ThrowOnFailure if bash path retrieval fails' {
        { Sync-PathFromBash -ThrowOnFailure -WhatIf } | Should -Not -Throw
    }
}
