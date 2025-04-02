BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\string.psm1" -Force
}

Describe "Get-LineBreak 函数测试" {
 
    It "检测CRLF换行符" {
        $content = "Line1`r`nLine2"
        Get-LineBreak -Content $content | Should -Be "`r`n"
    }

    It "检测LF换行符" {
        $content = "Line1`nLine2"
        Get-LineBreak -Content $content | Should -Be "`n"
    }

    It "没有换行符时返回默认值" {
        $content = "SingleLine"
        Get-LineBreak -Content $content | Should -Be "`n"
    }

    It "自定义默认换行符" {
        $content = "SingleLine"
        Get-LineBreak -Content $content -DefaultLineBreak "`r`n" | Should -Be "`r`n"
    }
}

Describe "Convert-JsoncToJson 函数测试" {
    BeforeAll {
        $testJsonc = @"
{
    // 这是注释
    "name": "test",
    "value": 123,
    /* 多行
    注释 */
    "array": [1, 2, 3,],
    "object": {
        "key": "value",
    }
}
"@
        $testJsoncPath = "$TestDrive\test.jsonc"
        $testJsonc | Out-File -FilePath $testJsoncPath -Encoding utf8

        # 新增带$schema的测试用例
        #         $testJsoncWithSchema = @"
        # {
        #     "`$schema": "http://json-schema.org/draft-07/schema#",
        #     // 带schema的配置
        #     "name": "schema_test",
        #     /**
        #      * 测试多行需求**/
        #     "config": {
        #         "url": "http://example.com",  // URL注释
        #         "path": "some//path"         // 包含//的字符串
        #     }
        # }
        # "@
        $testJsoncWithSchema = @"
{
    "`$schema": "http://json-schema.org/draft-07/schema#",
    // 带schema的配置
    "name": "schema_test",
    /**
     * 测试多行需求**/
    "config": {
        "url": "http://example.com",  
        "path": "some//path"      
    }
}
"@
        $testJsoncWithSchemaPath = "$TestDrive\test_with_schema.jsonc"
        $testJsoncWithSchema | Out-File -FilePath $testJsoncWithSchemaPath -Encoding utf8
    }

    It "成功转换JSONC到JSON" {
        $result = Convert-JsoncToJson -Path $testJsoncPath
        $result | Should -Not -BeNullOrEmpty
        $result | ConvertFrom-Json | ForEach-Object { $_.name } | Should -Be "test"
    }

    It "成功移除单行注释" {
        $result = Convert-JsoncToJson -Path $testJsoncPath
        $result -match "//" | Should -Be $false
    }

    It "成功移除多行注释" {
        $result = Convert-JsoncToJson -Path $testJsoncPath
        $result -match "/\*" | Should -Be $false
        $result -match "\*/" | Should -Be $false
    }

    It "成功移除尾随逗号" {
        $result = Convert-JsoncToJson -Path $testJsoncPath
        $result -match ',\s*]' | Should -Be $false
        $result -match ',\s*}' | Should -Be $false
    }

    It "输出到指定文件" {
        $outputPath = "$TestDrive\output.json"
        Convert-JsoncToJson -Path $testJsoncPath -OutputFilePath $outputPath *> $null
        Test-Path $outputPath | Should -Be $true
        Get-Content $outputPath -Raw | Should -Not -Match "//"
    }

    It "正确处理包含$schema的JSONC文件" {
        $result = Convert-JsoncToJson -Path $testJsoncWithSchemaPath 
        $result | Should -Not -BeNullOrEmpty
        $result | ConvertFrom-Json | ForEach-Object { $_.name } | Should -Be "schema_test"
        $result -match '\$schema' | Should -Be $false
    }

    It "保留字符串中的//不当作注释" {
        $result = Convert-JsoncToJson -Path $testJsoncWithSchemaPath
        $jsonObj = $result | ConvertFrom-Json
        $jsonObj.config.path | Should -Be "some//path"
    }
}