Import-Module (Join-Path $PSScriptRoot '..' 'psutils.psd1')

Describe 'Git 模块函数' {
    Context 'Get-GitIgnorePatterns 解析有效行' {
        BeforeAll {
            $testRoot = Join-Path $env:TEMP ("psutils_git_tests_" + [Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $testRoot | Out-Null
            $gitIgnore = Join-Path $testRoot '.gitignore'
            @(
                '# comment',
                '\#headline',
                '!important',
                '/build/',
                'dist/',
                'logs/',
                '/logs',
                'node_modules',
                '*.log',
                '*.tmp'
            ) | Set-Content -LiteralPath $gitIgnore -Encoding UTF8
        }

        It '应返回解析后的有效模式集合' {
            $patterns = Get-GitIgnorePatterns -GitIgnorePath $gitIgnore
            ($patterns) | Should -Not -Be $null
            $patterns | Should -Contain 'build'
            $patterns | Should -Contain 'dist'
            $patterns | Should -Contain 'logs'
            $patterns | Should -Contain 'node_modules'
            $patterns | Should -Contain '*.log'
            $patterns | Should -Contain '*.tmp'
            $patterns | Should -Contain '#headline'
            $patterns | Should -Not -Contain '!important'
            ((@($patterns | Where-Object { $_ -eq 'logs' }).Count)) | Should -Be 1
        }

        AfterAll {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }

    Context 'New-7ZipExcludeArgs 生成排除参数' {
        BeforeAll {
            $testRoot = Join-Path $env:TEMP ("psutils_git_tests_" + [Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $testRoot | Out-Null
            $gitIgnore = Join-Path $testRoot '.gitignore'
            @(
                '/build/',
                'logs/',
                'node_modules',
                '*.log'
            ) | Set-Content -LiteralPath $gitIgnore -Encoding UTF8
        }

        It '应合并基础、gitignore 和额外排除并去重' {
            $args = New-7ZipExcludeArgs -GitIgnorePath $gitIgnore -AdditionalExcludes @('dist','build/*.tmp','logs')
            ($args) | Should -Not -Be $null
            foreach ($a in $args) { $a | Should -Match '^-xr!.+' }
            $args | Should -Contain '-xr!node_modules'
            $args | Should -Contain '-xr!build'
            $args | Should -Contain '-xr!dist'
            $args | Should -Contain '-xr!logs'
            $args | Should -Contain '-xr!*.log'
            ((@($args | Where-Object { $_ -eq '-xr!logs' }).Count)) | Should -Be 1
        }

        AfterAll {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

