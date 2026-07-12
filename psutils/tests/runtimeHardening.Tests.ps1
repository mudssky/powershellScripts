Describe 'psutils 静默异常契约' {
    BeforeAll {
        $script:ModulesRoot = Join-Path $PSScriptRoot '..' 'modules'
    }

    It '可降级模块不保留完全空的 catch' -ForEach @('env', 'hardware', 'network', 'proxy') {
        $content = Get-Content -LiteralPath (Join-Path $script:ModulesRoot "$_.psm1") -Raw

        $content | Should -Not -Match 'catch\s*\{\s*\}'
    }
}

