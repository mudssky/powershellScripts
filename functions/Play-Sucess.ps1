function Play-Success {
    $path = "D:\code\cliTools\noticeAudio\success.wav"
    $playerStart = New-Object Media.SoundPlayer $path
    $playerStart.Load()
    $playerStart.PlaySync()   
}

Play-Success