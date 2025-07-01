<# )
.SYNOPSIS
    DVD文件压缩脚本

.DESCRIPTION
    该脚本用于压缩DVD文件（.vob格式）。根据文件大小自动选择压缩策略：
    - 小于等于10MB的文件转换为WebP格式
    - 大于10MB的文件使用x264编码器压缩为MKV格式
    支持可选的删除原始DVD文件功能。

.PARAMETER delete
    开关参数，如果指定则在压缩完成后删除原始DVD文件（.ifo, .vob, .bup）

.PARAMETER crf
    视频质量参数，默认值为23。数值越小质量越高，文件越大

.EXAMPLE
    .\dvdcompress.ps1
    压缩当前目录下的所有.vob文件，保留原始文件

.EXAMPLE
    .\dvdcompress.ps1 -delete
    压缩文件并删除原始DVD文件

.EXAMPLE
    .\dvdcompress.ps1 -crf 20 -delete
    使用更高质量设置压缩文件并删除原始文件

.NOTES
    需要安装ffmpeg工具
    只处理大于等于100KB的.vob文件
#>
param(
    [switch]$delete,
    [string]$crf = 23
)

Get-ChildItem *.vob | Where-Object { $_.Length -ge 100kb } | ForEach-Object {
    if ($_.Length -le 10mb ) {
        ffmpeg.exe -i $_.FullName  ($_.BaseName + '.webp')
    }
    else {
        ffmpeg.exe -i $_.FullName -vcodec libx264 -acodec flac -crf $crf -preset veryfast ($_.BaseName + '.mkv')
    } 
} 


if ($delete) {
    Write-Host -ForegroundColor Red "delete flag open, deleting dvd files(ifo,vob,bup)..."
    Remove-Item -Force *.ifo, *.vob, *.bup
}