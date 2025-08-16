<#
.SYNOPSIS
批量转换占用空间过大的图片为 WebP 格式

.DESCRIPTION
该脚本用于批量转换指定目录下占用空间过大的图片文件为 WebP 格式，以减少存储空间。
支持 PNG、BMP、TIF、JPG 等格式的图片转换，可以设置压缩阈值、自定义 FFmpeg 参数，
并支持无损压缩模式。转换完成后可选择删除原始文件。

.PARAMETER targetPath
需要处理的目标路径，默认为当前目录 ('.')

.PARAMETER limitSize
需要压缩的图片阈值大小（字节），小于这个数值的图片不进行压缩，默认为 3MB

.PARAMETER paramStr
自定义的 FFmpeg 参数字符串，用于控制压缩质量和其他选项，默认为空格

.PARAMETER ffmpegloglevel
FFmpeg 的日志等级，可选值：quiet、panic、fatal、error、warning、info、verbose、debug、trace，默认为 'warning'

.PARAMETER noDelete
开关参数，如果指定则不删除原始文件，保留转换前的图片

.PARAMETER lossless
开关参数，如果指定则使用无损压缩模式，会自动添加 '-lossless 1' 参数并将阈值设为 0

.EXAMPLE
webpCompress.ps1
使用默认设置压缩当前目录下大于 3MB 的图片

.EXAMPLE
webpCompress.ps1 -targetPath "C:\Pictures" -limitSize 10mb
压缩 C:\Pictures 目录下大于 10MB 的图片

.EXAMPLE
webpCompress.ps1 -limitSize 5mb -paramStr '-codec libwebp -vf scale=iw/2:ih/2 -lossless 0 -quality 80'
使用自定义参数压缩大于 5MB 的图片，缩放为原尺寸的一半，质量设为 80

.EXAMPLE
webpCompress.ps1 -lossless -noDelete
使用无损压缩模式处理所有图片，并保留原始文件

.NOTES
- 支持的图片格式：PNG、BMP、TIF、JPG
- 需要系统中安装 FFmpeg 工具
- 转换后的文件扩展名为 .webp
- 在无损模式下，-q 参数会影响压缩时间，默认为 75
- 脚本会递归处理指定目录下的所有子目录
#>
# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Scope='Function')]
# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Scope='Function')]
# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Scope='Function')] # 这个规则很蠢会误判
param(
    # 需要压缩的图片阈值大小，小于这个数值的图片不进行压缩
    [string]$targetPath = '.',
    [int]$limitSize = 3mb,
    [string]$paramStr = ' ',
    # [string]$paramStr='-codec libwebp -pix_fmt yuv420p -vf scale=iw:ih  -lossless 0 -quality 75',
    # 其实不用多设置，默认的设置就是最好的，默认压制出来的就是yuv420p
    #[string]$paramStr='-codec libwebp  -vf scale=iw:ih  -lossless 0 -quality 75',
    [string]$ffmpegloglevel = 'warning',
    [switch]$noDelete,
    [switch]$lossless

)

#只压缩png格式的图片，先检索目录下的png图片
$count = 0
$supportExt = '.png', '.bmp', '.tif', '.jpg'
if ($lossless) {
    # -q 在无损压缩的时候会影响压缩的时间，默认也是75，设为100最好，但是为了减少电脑运算负担，这里不做改动
    $paramStr += ' -lossless 1 '
    $limitSize = 0
}
# ffmpeg 的log等级有
# "quiet"
# "panic"
# "fatal"
# "error"
# "warning"
# "info"
# "verbose"
# "debug"
# "trace"


Get-ChildItem -Recurse -LiteralPath $targetPath | Where-Object { $_.Extension -in $supportExt } | ForEach-Object {
    if ($_.Length -gt $limitSize) {
        Write-Host -ForegroundColor Green "detect large png picture : $($_.FullName) size:$($_.Length/1mb)mb "

        $newfullname = $_.FullName.Substring(0, $_.FullName.Length - 4) + '.webp'
        Invoke-Expression "ffmpeg.exe  -loglevel $ffmpegloglevel  -i '$($_.FullName)'  $paramStr  '$($newfullname)'"
        # ffmpeg.exe -i $_.FullName  $paramStr  ($_.FullName.Substring(0,$_.FullName.Length-4)+'.webp')

        if ((Test-Path -LiteralPath $newfullname) -and (-not $noDelete)) {
            Remove-Item -Force -LiteralPath $_.FullName
            Write-Host -ForegroundColor yellow "delete $($_.FullName) complete "
            $count++
        }
        else {
            Write-Host -ForegroundColor red "not find the source file or no delete "
            #break
        }
    }
}

Write-Host -ForegroundColor  Green   "compress $count  picture  complete"





