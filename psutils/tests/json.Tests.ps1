BeforeAll {
    $script:JsonModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\json.psm1'))
    Import-Module $script:JsonModulePath -Force
}

Describe 'JSON helper' {
    It '读取 JSON 文件为 hashtable' {
        $path = Join-Path $TestDrive 'settings.json'
        Set-Content -LiteralPath $path -Encoding utf8NoBOM -Value '{"env":{"A":"1"}}'

        $value = Read-JsonHashtableFile -Path $path -Label 'settings.json'

        $value | Should -BeOfType [hashtable]
        $value.env.A | Should -Be '1'
    }

    It '解析失败时带上调用方标签' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $path -Encoding utf8NoBOM -Value '{ bad json'

        { Read-JsonHashtableFile -Path $path -Label '坏配置' } | Should -Throw '解析 坏配置 失败*'
    }

    It '原子写入 JSON 并清理临时文件' {
        $path = Join-Path $TestDrive 'out/settings.json'

        $result = Write-JsonFileAtomic -Path $path -Value @{ name = 'demo' } -TempPrefix 'settings'

        $result | Should -Be $path
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).name | Should -Be 'demo'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter '*.tmp').Count | Should -Be 0
    }

    It '为结构化值生成稳定键' {
        $key = Get-StableJsonKey -Value ([ordered]@{ a = 1; b = @('x', 'y') })

        $key | Should -Be '{"a":1,"b":["x","y"]}'
    }
}
