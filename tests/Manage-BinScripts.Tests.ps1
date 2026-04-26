Set-StrictMode -Version Latest

Describe 'Manage-BinScripts' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Manage-BinScripts.Tests.{0}" -f [System.Guid]::NewGuid())
        $script:ManageScript = Join-Path $script:TempRoot 'Manage-BinScripts.ps1'

        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $script:ProjectRoot 'Manage-BinScripts.ps1') -Destination $script:ManageScript -Force
        Copy-Item `
            -Path (Join-Path $script:ProjectRoot 'psutils/src/config') `
            -Destination (Join-Path $script:TempRoot 'psutils/src/config') `
            -Recurse `
            -Force

        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/pwsh/a') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/pwsh/b') -Force | Out-Null

        Set-Content -Path (Join-Path $script:TempRoot 'scripts/pwsh/a/A.ps1') -Value "Write-Output 'A'" -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:TempRoot 'scripts/pwsh/b/B.ps1') -Value "Write-Output 'B'" -Encoding utf8NoBOM
    }

    AfterEach {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It 'removes stale renamed shims and preserves unrelated shims during partial sync' {
        # 这里断言的是产物状态，不需要把脚本执行日志带进默认门禁输出。
        & $script:ManageScript -Action sync -Force *> $null

        $binDir = Join-Path $script:TempRoot 'bin'
        Test-Path -LiteralPath (Join-Path $binDir 'A.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $binDir 'B.ps1') | Should -BeTrue

        Rename-Item -LiteralPath (Join-Path $script:TempRoot 'scripts/pwsh/a/A.ps1') -NewName 'A2.ps1'

        & $script:ManageScript -Action sync -Force -Patterns @('scripts/pwsh/a/*.ps1') *> $null

        Test-Path -LiteralPath (Join-Path $binDir 'A.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $binDir 'A2.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $binDir 'B.ps1') | Should -BeTrue
    }

    It 'installs directory tools from tool.psd1 and hides internal scripts' {
        $toolRoot = Join-Path $script:TempRoot 'scripts/pwsh/ai/agent-runner'
        New-Item -ItemType Directory -Path (Join-Path $toolRoot 'core') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $toolRoot 'agents') -Force | Out-Null

        Set-Content -Path (Join-Path $toolRoot 'tool.psd1') -Encoding utf8NoBOM -Value @'
@{
    BinName = 'Invoke-AiAgent.ps1'
    Entry   = 'main.ps1'
}
'@
        Set-Content -Path (Join-Path $toolRoot 'main.ps1') -Encoding utf8NoBOM -Value @'
[CmdletBinding()]
param([string]$CommandName)
Write-Output "main:$CommandName"
'@
        Set-Content -Path (Join-Path $toolRoot 'core/prompt.ps1') -Encoding utf8NoBOM -Value "Write-Output 'internal-core'"
        Set-Content -Path (Join-Path $toolRoot 'agents/codex.ps1') -Encoding utf8NoBOM -Value "Write-Output 'internal-agent'"

        & $script:ManageScript -Action sync -Force *> $null

        $binDir = Join-Path $script:TempRoot 'bin'
        Test-Path -LiteralPath (Join-Path $binDir 'Invoke-AiAgent.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $binDir 'main.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $binDir 'prompt.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $binDir 'codex.ps1') | Should -BeFalse

        $shim = Get-Content -LiteralPath (Join-Path $binDir 'Invoke-AiAgent.ps1') -Raw
        $shim | Should -Match 'agent-runner[/\\]main\.ps1'
    }

    It 'fails when a directory tool manifest points at a missing entry script' {
        $toolRoot = Join-Path $script:TempRoot 'scripts/pwsh/ai/broken-tool'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Set-Content -Path (Join-Path $toolRoot 'tool.psd1') -Encoding utf8NoBOM -Value @'
@{
    BinName = 'Broken.ps1'
    Entry   = 'missing.ps1'
}
'@

        { & $script:ManageScript -Action sync -Force *> $null } | Should -Throw '*目录工具入口不存在*'
    }
}
