$privateCommandsByModule = @{
    docker = @(
        'Get-WslDockerCandidateDistro'
        'Get-WslDockerEnvironmentArgument'
        'Resolve-WslDockerDistro'
        'Test-DockerDesktopDaemonAvailable'
        'Test-WindowsDockerDaemonAvailable'
        'Test-WslDockerEngineAvailable'
    )
    filesystem = @(
        'Build-TreeObject'
        'Get-GitignoreRules'
        'Get-ItemColor'
        'Show-TreeItem'
        'Test-GitignoreMatch'
    )
    help = @('Convert-HelpBlock')
    install = @('Get-PackageInstallCommand')
    test = @(
        'Test-ArrayNotNull'
        'Test-HomebrewFormula'
        'Test-MacOSApplicationInstalled'
        'Test-MacOSCaskApp'
    )
}

$diagnosticCommandsByModule = @{
    error = @('Debug-CommandExecution')
    help = @('Test-HelpSearchPerformance')
    pwsh = @('Out-ModuleToFile')
    test = @('Clear-EXEProgramCache')
}

BeforeAll {
    $script:ModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:ManifestPath = Join-Path $script:ModuleRoot 'psutils.psd1'
    $script:ModulesRoot = Join-Path $script:ModuleRoot 'modules'
    $script:ManifestData = Import-PowerShellDataFile $script:ManifestPath
    $script:PrivateCommandNames = @(
        'Build-TreeObject', 'Convert-HelpBlock', 'Get-GitignoreRules', 'Get-ItemColor',
        'Get-PackageInstallCommand', 'Get-WslDockerCandidateDistro', 'Get-WslDockerEnvironmentArgument',
        'Resolve-WslDockerDistro', 'Show-TreeItem', 'Test-ArrayNotNull',
        'Test-DockerDesktopDaemonAvailable', 'Test-GitignoreMatch', 'Test-HomebrewFormula',
        'Test-MacOSApplicationInstalled', 'Test-MacOSCaskApp', 'Test-WindowsDockerDaemonAvailable',
        'Test-WslDockerEngineAvailable'
    )
    $script:DiagnosticCommandNames = @(
        'Clear-EXEProgramCache', 'Debug-CommandExecution', 'Out-ModuleToFile', 'Test-HelpSearchPerformance'
    )
}

Describe 'psutils API 分层契约' {
    BeforeEach {
        Remove-Module psutils, docker, filesystem, help, install, test, error, pwsh, wrapper, string -Force -ErrorAction SilentlyContinue
    }

    It '聚合 manifest 只保留稳定、共享和兼容 API' {
        $declaredNames = @($script:ManifestData.FunctionsToExport)

        $declaredNames.Count | Should -Be 109
        foreach ($name in @($script:PrivateCommandNames + $script:DiagnosticCommandNames)) {
            $declaredNames | Should -Not -Contain $name
        }
        foreach ($name in @('Search-ModuleHelp', 'Find-PSUtilsFunction', 'Get-FunctionHelp')) {
            $declaredNames | Should -Contain $name
        }
    }

    It 'Private 命令不从对应子模块导出' -ForEach @(
        foreach ($entry in $privateCommandsByModule.GetEnumerator()) {
            @{ ModuleName = $entry.Key; CommandNames = @($entry.Value) }
        }
    ) {
        Import-Module (Join-Path $script:ModulesRoot "$ModuleName.psm1") -Force

        foreach ($name in $CommandNames) {
            Get-Command $name -Module $ModuleName -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'Diagnostic 命令只保留子模块直导入口' -ForEach @(
        foreach ($entry in $diagnosticCommandsByModule.GetEnumerator()) {
            @{ ModuleName = $entry.Key; CommandNames = @($entry.Value) }
        }
    ) {
        Import-Module $script:ManifestPath -Force
        foreach ($name in $CommandNames) {
            Get-Command $name -Module psutils -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        Remove-Module psutils -Force

        Import-Module (Join-Path $script:ModulesRoot "$ModuleName.psm1") -Force
        foreach ($name in $CommandNames) {
            Get-Command $name -Module $ModuleName -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'wrapper 和 string 使用精确导出集合' -ForEach @(
        @{ ModuleName = 'wrapper'; ExpectedNames = @('Get-CustomAlias', 'Set-CustomAlias') }
        @{ ModuleName = 'string'; ExpectedNames = @('Convert-JsoncToJson', 'Get-LineBreak') }
    ) {
        $modulePath = Join-Path $script:ModulesRoot "$ModuleName.psm1"
        Import-Module $modulePath -Force
        $actualNames = @(
            Get-Command -Module $ModuleName -CommandType Function |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )

        $actualNames | Should -Be $ExpectedNames
        Get-Content -LiteralPath $modulePath -Raw | Should -Not -Match 'Export-ModuleMember\s+-Function\s+\*'
    }

    It '导入 wrapper 不创建全局默认前缀变量' {
        Remove-Variable -Name DefaultAliasDespPrefix -Scope Global -ErrorAction SilentlyContinue

        Import-Module (Join-Path $script:ModulesRoot 'wrapper.psm1') -Force

        Get-Variable -Name DefaultAliasDespPrefix -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It '所有聚合公共函数都有返回值和显式参数说明' {
        Import-Module $script:ManifestPath -Force
        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($command in Get-Command -Module psutils -CommandType Function) {
            $help = Get-Help $command.Name -Full
            $returnValuesProperty = $help.PSObject.Properties['returnValues']
            $outputs = if ($null -eq $returnValuesProperty) {
                ''
            }
            else {
                @($returnValuesProperty.Value.returnValue | ForEach-Object { [string]$_.type.name }) -join ','
            }
            if ([string]::IsNullOrWhiteSpace($outputs)) {
                $failures.Add("$($command.Name): 缺少 .OUTPUTS")
            }

            $parametersProperty = $help.PSObject.Properties['parameters']
            $parameterItemsProperty = if ($null -eq $parametersProperty) {
                $null
            }
            else {
                $parametersProperty.Value.PSObject.Properties['parameter']
            }
            $parameters = if ($null -eq $parameterItemsProperty) { @() } else { @($parameterItemsProperty.Value) }
            foreach ($parameter in $parameters) {
                if ([string]::IsNullOrWhiteSpace([string]$parameter.name) -or $parameter.name -in @('WhatIf', 'Confirm')) {
                    continue
                }
                $descriptionProperty = $parameter.PSObject.Properties['description']
                $description = if ($null -eq $descriptionProperty) {
                    ''
                }
                else {
                    @($descriptionProperty.Value.Text) -join ' '
                }
                if ([string]::IsNullOrWhiteSpace($description)) {
                    $failures.Add("$($command.Name): 参数 $($parameter.name) 缺少说明")
                }
            }
        }

        $failures | Should -BeNullOrEmpty
    }
}

AfterAll {
    Remove-Module psutils, docker, filesystem, help, install, test, error, pwsh, wrapper, string -Force -ErrorAction SilentlyContinue
}
