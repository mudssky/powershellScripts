Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    . (Join-Path $script:RepoRoot 'scripts/pwsh/devops/build/dependency-resolver.ps1')
}

Describe 'Get-BundleFunctionIndex' {
    It 'throws when the shared source roots define the same function twice' {
        $sharedRoot = Join-Path $TestDrive 'shared-duplicate'
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null
        Set-Content -Path (Join-Path $sharedRoot 'first.ps1') -Value @'
function Resolve-ConfigSources { return @{} }
'@
        Set-Content -Path (Join-Path $sharedRoot 'second.ps1') -Value @'
function Resolve-ConfigSources { return @{} }
'@

        { Get-BundleFunctionIndex -RootPaths @($sharedRoot) } | Should -Throw '重复函数定义'
    }
}

Describe 'Get-BundleFunctionClosure' {
    It 'collects transitive shared dependencies in dependency-first order' {
        $entryRoot = Join-Path $TestDrive 'entry'
        $sharedRoot = Join-Path $TestDrive 'shared'
        New-Item -ItemType Directory -Path $entryRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null

        $entryPath = Join-Path $entryRoot 'context.ps1'
        Set-Content -Path $entryPath -Value @'
function Resolve-PgContext {
    Resolve-ConfigSources | Out-Null
}
'@

        Set-Content -Path (Join-Path $sharedRoot 'config.ps1') -Value @'
function ConvertTo-ConfigHashtable {
    param([object]$InputObject)
    return @{}
}

function Resolve-ConfigSources {
    ConvertTo-ConfigHashtable -InputObject @{} | Out-Null
    return @{}
}
'@

        $index = Get-BundleFunctionIndex -RootPaths @($sharedRoot)
        $closure = Get-BundleFunctionClosure -EntryPaths @($entryPath) -FunctionIndex $index

        $closure.FunctionNames | Should -Be @('ConvertTo-ConfigHashtable', 'Resolve-ConfigSources')
    }

    It 'throws when a referenced shared function cannot be found' {
        $entryRoot = Join-Path $TestDrive 'entry-missing'
        $sharedRoot = Join-Path $TestDrive 'shared-empty'
        New-Item -ItemType Directory -Path $entryRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null

        $entryPath = Join-Path $entryRoot 'context.ps1'
        Set-Content -Path $entryPath -Value @'
function Resolve-PgContext {
    Resolve-ConfigSources | Out-Null
}
'@

        $index = Get-BundleFunctionIndex -RootPaths @($sharedRoot)

        { Get-BundleFunctionClosure -EntryPaths @($entryPath) -FunctionIndex $index } | Should -Throw '未找到共享函数定义'
    }
}
