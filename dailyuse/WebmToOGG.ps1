# WebmToOGG
ls -Recurse *.webm | foreach{ffmpeg.exe -i $_.FullName -acodec copy ($_.FullName.TrimEnd('.webm')+'.opus')}
