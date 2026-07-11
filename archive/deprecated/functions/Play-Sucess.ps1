<#
.SYNOPSIS
    播放成功提示音

.DESCRIPTION
    播放指定路径的WAV音频文件作为成功操作的提示音。
    使用.NET的Media.SoundPlayer类同步播放音频文件。

.OUTPUTS
    无返回值，直接播放音频

.EXAMPLE
    PlaySuccess
    播放成功提示音

.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    注意: 音频文件路径是硬编码的，需要确保文件存在
    状态: 已弃用 - 此函数位于deprecated目录中
#>
function PlaySuccess {
    $path = "D:\code\cliTools\noticeAudio\success.wav"
    $playerStart = New-Object Media.SoundPlayer $path
    $playerStart.Load()
    $playerStart.PlaySync()   
}

PlaySuccess