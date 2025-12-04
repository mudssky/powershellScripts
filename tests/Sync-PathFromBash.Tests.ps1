Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/../psutils/modules/env.psm1" -Force

Describe 'Sync-PathFromBash basic behavior' {
    It 'should return object with fields when ReturnObject=true' {
        $result = Sync-PathFromBash -WhatIf -ReturnObject
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
}
