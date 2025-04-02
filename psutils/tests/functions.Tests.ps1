BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\functions.psm1" -Force
}

Describe "Get-HistoryCommandRank 函数测试" {
    It "返回历史命令排名" -Skip {
        $result = Get-HistoryCommandRank -top 5
        $result | Should -Not -BeNullOrEmpty
    }
}


Describe "New-Shortcut 函数测试" {
    BeforeAll {
        $testTarget = "$TestDrive\target.txt"
        "" | Out-File -FilePath $testTarget -Encoding utf8
        $testShortcut = "$TestDrive\shortcut.lnk"
    }

    It "成功创建快捷方式" {
        { New-Shortcut -Path $testTarget -Destination $testShortcut } | Should -Not -Throw
        Test-Path $testShortcut | Should -Be $true
    }
}