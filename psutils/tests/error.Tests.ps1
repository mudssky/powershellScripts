BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\error.psm1" -Force
}

Describe "Debug-CommandExecution 函数测试" {
    It "成功执行命令时返回true" {
        $result = Debug-CommandExecution -CommandName "Get-Command" -Verbosity Silent
        $result | Should -Be $True
    }
}