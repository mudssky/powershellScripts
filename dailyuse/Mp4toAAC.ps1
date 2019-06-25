# Mp4toAAC   Mp4封装 即 h264视频流 + aac 音频流，抽取aac相当于直接拷贝视频中的音频流就没有转码的损失
$count=0;ls -File -Recurse  *.mp4 | foreach{ ffmpeg -i $_.FullName -acodec copy -vn  ($_.FullName.Substring(0,$_.FullName.IndexOf('.'))+'.aac');$count+=1};"mp4 counts:"+$count
