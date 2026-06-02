BeforeAll {
    $script:ProcessModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\process.psm1'))
    Import-Module $script:ProcessModulePath -Force
    $script:PwshPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

Describe 'process 模块命令预览与日志' {
    It '格式化包含空格和引号的参数' {
        $line = Format-NativeCommandLine -Command 'tool' -ArgumentList @('simple', 'has space', 'a"b')

        $line | Should -Be 'tool simple "has space" "a\"b"'
    }

    It '创建日志文件并追加带时间戳的日志行' {
        $logPath = New-CommandLogFile -LogDirectory (Join-Path $TestDrive 'logs') -Prefix 'demo' -Header 'demo header'

        Write-CommandLogLine -LogPath $logPath -Message 'hello'

        Test-Path -LiteralPath $logPath | Should -BeTrue
        $content = Get-Content -Raw -LiteralPath $logPath
        $content | Should -Match 'demo header'
        $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] hello'
    }

    It '日志路径为空时不写入也不报错' {
        { Write-CommandLogLine -LogPath '' -Message 'ignored' } | Should -Not -Throw
    }
}

Describe 'Invoke-NativeCommand' {
    It '成功执行外部命令并记录退出码' {
        $logPath = Join-Path $TestDrive 'native-command.log'

        $result = Invoke-NativeCommand `
            -Command $script:PwshPath `
            -ArgumentList @('-NoLogo', '-NoProfile', '-Command', 'Write-Output "ok"') `
            -WorkingDirectory $TestDrive `
            -LogPath $logPath `
            -SuppressOutput

        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Match 'ok'
        Get-Content -Raw -LiteralPath $logPath | Should -Match 'EXIT 0'
    }

    It 'AllowFailure 打开时返回非零退出结果' {
        $result = Invoke-NativeCommand `
            -Command $script:PwshPath `
            -ArgumentList @('-NoLogo', '-NoProfile', '-Command', 'exit 7') `
            -WorkingDirectory $TestDrive `
            -AllowFailure `
            -SuppressOutput

        $result.ExitCode | Should -Be 7
    }

    It '非零退出且未允许失败时抛出明确错误' {
        {
            Invoke-NativeCommand `
                -Command $script:PwshPath `
                -ArgumentList @('-NoLogo', '-NoProfile', '-Command', 'exit 5') `
                -WorkingDirectory $TestDrive `
                -SuppressOutput
        } | Should -Throw '外部命令执行失败(5):*'
    }
}
