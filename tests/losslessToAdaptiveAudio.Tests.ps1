Import-Module Pester -ErrorAction SilentlyContinue

Describe 'losslessToAdaptiveAudio encoder selection' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'misc' 'losslessToAdaptiveAudio.ps1'
        . (Resolve-Path $scriptPath) -targetPath $TestDrive -ThrottleLimit 1 -WhatIf
    }

    It '新脚本路径存在' {
        $newScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'misc' 'losslessToAdaptiveAudio.ps1'
        Test-Path -LiteralPath $newScriptPath | Should -BeTrue
    }

    It 'qaac 可用时选择 qaac' {
        Mock -CommandName Get-Command -MockWith {
            param([string]$Name)
            if ($Name -eq 'qaac.exe') {
                return [pscustomobject]@{ Name = 'qaac.exe' }
            }
            return $null
        }

        (Resolve-EncoderMode) | Should -Be 'qaac'
    }

    It 'qaac 不可用且 ffmpeg 可用时选择 ffmpeg-opus' {
        Mock -CommandName Get-Command -MockWith {
            param([string]$Name)
            if ($Name -eq 'ffmpeg') {
                return [pscustomobject]@{ Name = 'ffmpeg' }
            }
            return $null
        }

        (Resolve-EncoderMode) | Should -Be 'ffmpeg-opus'
    }

    It 'qaac 与 ffmpeg 都不可用时抛错' {
        Mock -CommandName Get-Command -MockWith {
            return $null
        }

        { Resolve-EncoderMode } | Should -Throw
    }

    It 'ffmpeg-opus 模式输出扩展名为 .ogg' {
        (Get-OutputExtension -EncoderMode 'ffmpeg-opus') | Should -Be '.ogg'
    }

    It 'ffmpeg-opus 命令包含 libopus 与 256k 参数' {
        $cmd = New-EncodeCommand -EncoderMode 'ffmpeg-opus' -InputPath 'C:\a.flac' -OutputPath 'C:\a.ogg' -QaacParam '--verbose'

        $cmd | Should -Match '-c:a libopus'
        $cmd | Should -Match '-b:a 256k'
    }

    It 'qaac 命令包含 qaac.exe 与 -o' {
        $cmd = New-EncodeCommand -EncoderMode 'qaac' -InputPath 'C:\a.flac' -OutputPath 'C:\a.m4a' -QaacParam '--verbose --rate keep -v320 -q2 --copy-artwork'

        $cmd | Should -Match '^qaac\.exe'
        $cmd | Should -Match ' -o '
    }
}
