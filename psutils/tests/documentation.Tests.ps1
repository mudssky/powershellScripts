$exampleFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot '../examples') -Filter '*.ps1' -File
)

BeforeAll {
    $script:ModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:ManifestPath = Join-Path $script:ModuleRoot 'psutils.psd1'
    $script:ReadmePath = Join-Path $script:ModuleRoot 'README.md'
    $script:ExamplesPath = Join-Path $script:ModuleRoot 'examples'
    $script:ManifestData = Import-PowerShellDataFile $script:ManifestPath
    $script:ReadmeContent = Get-Content -Path $script:ReadmePath -Raw
    $script:PwshPath = (Get-Process -Id $PID).Path
}

Describe 'psutils 文档事实契约' {
    It 'README 与 manifest 的版本和运行时要求一致' {
        $script:ReadmeContent | Should -Match ([regex]::Escape("模块版本：$($script:ManifestData.ModuleVersion)"))
        $script:ReadmeContent | Should -Match ([regex]::Escape("PowerShell：$($script:ManifestData.PowerShellVersion)+ Core"))
        $script:ReadmeContent | Should -Match 'Import-Module ./psutils/psutils\.psd1 -Force'
    }

    It 'README 不包含已知的过时事实' {
        $script:ReadmeContent | Should -Not -Match '15 个独立功能模块'
        $script:ReadmeContent | Should -Not -Match '(?i)ffmpeg'
        $script:ReadmeContent | Should -Not -Match 'PowerShell 版本.*5\.1'
        $script:ReadmeContent | Should -Not -Match 'ExpirationMinutes|CacheDirectory\s+"'
    }

    It 'README 只在迁移说明中提及弃用帮助 API' {
        $script:ReadmeContent | Should -Match 'Search-ModuleHelp.*已弃用'
        $script:ReadmeContent | Should -Not -Match '(?m)^\s*(Search-ModuleHelp|Find-PSUtilsFunction|Get-FunctionHelp)\b'
    }

    It 'Get-Tree 文档使用规范入口并覆盖当前公共参数' {
        $treeDocument = Get-Content -Path (Join-Path $script:ModuleRoot 'docs/Get-Tree.md') -Raw
        $treeDocument | Should -Match 'Import-Module ./psutils/psutils\.psd1 -Force'

        Import-Module $script:ManifestPath -Force
        $parameterNames = @((Get-Command Get-Tree -Module psutils).Parameters.Keys)
        foreach ($name in @('Path', 'MaxDepth', 'ShowFiles', 'ShowHidden', 'Exclude', 'MaxItems', 'UseGitignore', 'AsObject')) {
            $parameterNames | Should -Contain $name
            $treeDocument | Should -Match ([regex]::Escape(('`{0}`' -f $name)))
        }
    }
}

Describe 'psutils 活动示例 smoke 契约' {
    It '所有示例都能通过 PowerShell AST 解析' -ForEach $exampleFiles {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null

        $parseErrors | Should -BeNullOrEmpty
    }

    It '示例不再依赖弃用入口或帮助搜索 API' -ForEach $exampleFiles {
        $content = Get-Content -Path $_.FullName -Raw

        $content | Should -Not -Match 'index\.psm1'
        $content | Should -Not -Match '\b(Search-ModuleHelp|Find-PSUtilsFunction|Get-FunctionHelp)\b'
    }

    It '示例中的 Import-Module 字面量路径都存在' -ForEach $exampleFiles {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
        $imports = @(
            $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Import-Module'
                }, $true)
        )

        foreach ($import in $imports) {
            $pathElement = $import.CommandElements | Select-Object -Skip 1 -First 1
            $quoteCharacters = [char[]]@([char]34, [char]39)
            $pathText = $pathElement.Extent.Text.Trim($quoteCharacters)
            $resolvedPath = $pathText.Replace('$PSScriptRoot', $_.DirectoryName)
            $fullPath = [System.IO.Path]::GetFullPath($resolvedPath)

            Test-Path -LiteralPath $fullPath | Should -BeTrue
        }
    }

    It '帮助示例可以无交互执行' {
        $output = @(& $script:PwshPath -NoProfile -File (Join-Path $script:ExamplesPath 'help-search-examples.ps1') -SmokeTest 2>&1)

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }

    It '树示例可以在受限范围内执行' {
        $output = @(& $script:PwshPath -NoProfile -File (Join-Path $script:ExamplesPath 'tree-examples.ps1') -SmokeTest 2>&1)

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }

    It '脚本帮助示例可以使用最小参数执行' {
        $output = @(& $script:PwshPath -NoProfile -File (Join-Path $script:ExamplesPath 'test-script-example.ps1') -Name Smoke -Count 1 2>&1)

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
}

AfterAll {
    Remove-Module psutils -Force -ErrorAction SilentlyContinue
}
