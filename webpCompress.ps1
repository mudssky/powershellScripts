<#
.synopsis
批量转换占用空间过大的图片
.example

使用方法如下
allPngtoWebp.ps1 -limitSize 10mb -paramStr '-codec libwebp -vf scale=iw/4:ih/4 -lossless 1 -quality 100 -pix_fmt yuv420p'


#>
param(
# 需要压缩的图片阈值大小，小于这个数值的图片不进行压缩
[string]$targetPath='.',
[int]$limitSize=3mb,
[string]$paramStr=' ',
# [string]$paramStr='-codec libwebp -pix_fmt yuv420p -vf scale=iw:ih  -lossless 0 -quality 75',
# 其实不用多设置，默认的设置就是最好的，默认压制出来的就是yuv420p
#[string]$paramStr='-codec libwebp  -vf scale=iw:ih  -lossless 0 -quality 75',
[switch]$noDelete,
[switch]$lossless
)

#只压缩png格式的图片，先检索目录下的png图片
$count=0
$supportExt='.png','.bmp','.tif','.jpg'
if($lossless){
# -q 在无损压缩的时候会影响压缩的时间，默认也是75，设为100最好，但是为了减少电脑运算负担，这里不做改动
$paramStr+=' -lossless 1 '
$limitSize=0
}

Get-ChildItem -Recurse -LiteralPath $targetPath| where{$_.Extension -in $supportExt } | foreach{
if($_.Length -gt $limitSize){
     Write-Host -ForegroundColor Green "detect large png picture : $($_.FullName) size:$($_.Length/1mb)mb "
     
     $newfullname=$_.FullName.Substring(0,$_.FullName.Length-4)+'.webp'
     Invoke-Expression "ffmpeg.exe -i '$($_.FullName)'  $paramStr  '$($newfullname)'"
    # ffmpeg.exe -i $_.FullName  $paramStr  ($_.FullName.Substring(0,$_.FullName.Length-4)+'.webp')

    if ((Test-Path -LiteralPath $newfullname)-and (-not $noDelete)){
        rm -Force -LiteralPath $_.FullName
        Write-Host -ForegroundColor yellow "delete $($_.FullName) complete "
     $count++
     }
     else{
        Write-Host -ForegroundColor red "not find the source file or no delete "
        #break
     }
    }
}

Write-Host -ForegroundColor  Green   "compress $count  picture  complete"





