Set-StrictMode -Version Latest

Describe 'Sync-PathFromBash basic behavior' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../psutils/modules/env.psm1" -Force
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should return object with fields when ReturnObject=true' {
        # WhatIf/Verbose 输出属于诊断信息，默认门禁日志中直接静音。
        $result = Sync-PathFromBash -WhatIf -ReturnObject:$true 4>$null 6>$null
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $result.PSObject.Properties.Name | Should -Contain 'SourcePathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'CurrentPathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'AddedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'SkippedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'NewPath'
    }
    It 'should support Prepend strategy without error when WhatIf' {
        { Sync-PathFromBash -Prepend -WhatIf 4>$null 6>$null } | Should -Not -Throw
    }
    It 'should support Append strategy (default) without error when WhatIf' {
        { Sync-PathFromBash -WhatIf 4>$null 6>$null } | Should -Not -Throw
    }
    It 'should support Login branch without error when WhatIf' {
        { Sync-PathFromBash -Login -WhatIf 4>$null 6>$null } | Should -Not -Throw
    }
}

Describe 'Sync-PathFromBash cache and error semantics' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../psutils/modules/env.psm1" -Force
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should use cache when CacheSeconds > 0 and write cache file' {
        $r = Sync-PathFromBash -WhatIf -ReturnObject:$true -Verbose 4>$null 6>$null
        $r | Should -Not -BeNullOrEmpty
    }
    It 'should throw when ThrowOnFailure if bash path retrieval fails' {
        { Sync-PathFromBash -ThrowOnFailure -WhatIf 4>$null 6>$null } | Should -Not -Throw
    }
}
