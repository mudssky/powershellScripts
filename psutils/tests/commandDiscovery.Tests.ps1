BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\commandDiscovery.psm1" -Force
    $script:OriginalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
    $script:OriginalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
    # 测试会临时覆写 PATH，因此在进入各个用例前先解析 chmod 的绝对路径，避免 Unix 下创建测试命令失败。
    $script:ChmodPath = if ($IsWindows) { $null } else { (Get-Command chmod -ErrorAction Stop).Source }
}

AfterAll {
    [Environment]::SetEnvironmentVariable('PATH', $script:OriginalPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $script:OriginalPathExt, 'Process')
    Remove-Item Function:\New-TestExecutableCommand -ErrorAction SilentlyContinue
}

function global:New-TestExecutableCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($IsWindows) {
        $commandPath = Join-Path $Directory "$Name.cmd"
        Set-Content -Path $commandPath -Value "@echo off`r`nexit /b 0" -Encoding ascii
        return $commandPath
    }

    $commandPath = Join-Path $Directory $Name
    Set-Content -Path $commandPath -Value "#!/usr/bin/env sh`necho ok" -Encoding ascii
    & $script:ChmodPath +x $commandPath
    return $commandPath
}

Describe 'Find-ExecutableCommand 函数测试' {
    BeforeEach {
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        $script:TempDirA = Join-Path $script:TempRoot 'a'
        $script:TempDirB = Join-Path $script:TempRoot 'b'
        New-Item -ItemType Directory -Path $script:TempDirA -Force | Out-Null
        New-Item -ItemType Directory -Path $script:TempDirB -Force | Out-Null

        [Environment]::SetEnvironmentVariable('PATH', $script:TempDirA, 'Process')
        if ($IsWindows) {
            [Environment]::SetEnvironmentVariable('PATHEXT', '.COM;.EXE;.BAT;.CMD', 'Process')
        }
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('PATH', $script:OriginalPath, 'Process')
        [Environment]::SetEnvironmentVariable('PATHEXT', $script:OriginalPathExt, 'Process')
        Remove-Item -Path $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '检测存在的命令时应返回对象结果' {
        $commandName = "pwsh-test-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
        $commandPath = New-TestExecutableCommand -Directory $script:TempDirA -Name $commandName

        $result = Find-ExecutableCommand -Name $commandName

        $result.Name | Should -Be $commandName
        $result.Found | Should -Be $true
        $result.Path | Should -Be $commandPath
    }

    It '检测不存在的命令时应返回 Found false' {
        $result = Find-ExecutableCommand -Name "missing-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"

        $result.Found | Should -Be $false
        $result.Path | Should -BeNullOrEmpty
    }

    It '默认不缓存未命中结果' {
        $commandName = "nocache-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"

        $firstResult = Find-ExecutableCommand -Name $commandName
        $firstResult.Found | Should -Be $false

        $commandPath = New-TestExecutableCommand -Directory $script:TempDirA -Name $commandName
        $secondResult = Find-ExecutableCommand -Name $commandName

        $secondResult.Found | Should -Be $true
        $secondResult.Path | Should -Be $commandPath
    }

    It '显式开启 CacheMisses 后应缓存未命中结果直到 NoCache' {
        $commandName = "cachemiss-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"

        $firstResult = Find-ExecutableCommand -Name $commandName -CacheMisses
        $firstResult.Found | Should -Be $false

        $commandPath = New-TestExecutableCommand -Directory $script:TempDirA -Name $commandName
        $cachedResult = Find-ExecutableCommand -Name $commandName -CacheMisses
        $cachedResult.Found | Should -Be $false

        $freshResult = Find-ExecutableCommand -Name $commandName -NoCache
        $freshResult.Found | Should -Be $true
        $freshResult.Path | Should -Be $commandPath
    }

    It '使用 AllMatches 时应返回所有命中路径并保持 PATH 顺序' {
        $commandName = "allmatches-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
        $commandPathA = New-TestExecutableCommand -Directory $script:TempDirA -Name $commandName
        $commandPathB = New-TestExecutableCommand -Directory $script:TempDirB -Name $commandName
        $separator = [System.IO.Path]::PathSeparator
        [Environment]::SetEnvironmentVariable('PATH', "$($script:TempDirA)$separator$($script:TempDirB)", 'Process')

        $result = Find-ExecutableCommand -Name $commandName -AllMatches

        $result.Found | Should -Be $true
        $result.Path | Should -Be $commandPathA
        @($result.AllPaths).Count | Should -Be 2
        $result.AllPaths[0] | Should -Be $commandPathA
        $result.AllPaths[1] | Should -Be $commandPathB
    }

    It '应支持批量输入并保留结果顺序' {
        $presentCommand = "batch-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
        $missingCommand = "missing-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
        $commandPath = New-TestExecutableCommand -Directory $script:TempDirA -Name $presentCommand

        $results = @(Find-ExecutableCommand -Name @($presentCommand, $missingCommand))

        $results.Count | Should -Be 2
        $results[0].Name | Should -Be $presentCommand
        $results[0].Found | Should -Be $true
        $results[0].Path | Should -Be $commandPath
        $results[1].Name | Should -Be $missingCommand
        $results[1].Found | Should -Be $false
    }
}
