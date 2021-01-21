param(
[string]$url,
[string]$filename='out.mp4'
)


streamlink.exe $url best --hls-segment-thread 10 -o $filename