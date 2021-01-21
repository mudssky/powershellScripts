<#
.synopsis
����ת��ռ�ÿռ�����ͼƬ
.example

ʹ�÷�������
allPngtoWebp.ps1 -limitSize 10mb -paramStr '-codec libwebp -vf scale=iw/4:ih/4 -lossless 1 -quality 100 -pix_fmt yuv420p'


#>
param(
# ��Ҫѹ����ͼƬ��ֵ��С��С�������ֵ��ͼƬ������ѹ��
[string]$targetPath='.',
[int]$limitSize=10mb,
[string]$paramStr='-codec libwebp -pix_fmt yuv420p -vf scale=iw:ih  -lossless 0 -quality 75',
# ��ʵ���ö����ã�Ĭ�ϵ����þ�����õģ�Ĭ��ѹ�Ƴ����ľ���yuv420p
#[string]$paramStr='-codec libwebp  -vf scale=iw:ih  -lossless 0 -quality 75',
[switch]$noDelete
)

#ֻѹ��png��ʽ��ͼƬ���ȼ���Ŀ¼�µ�pngͼƬ
$count=0
Get-ChildItem -Recurse -LiteralPath $targetPath| where{$_.Extension -eq '.png'} | foreach{
if($_.Length -gt $limitSize){
     Write-Host -ForegroundColor Green "detect large png picture : $($_.FullName) size:$($_.Length/1mb) "
     
     $newfullname=$_.FullName.Substring(0,$_.FullName.Length-4)+'.webp'
     Invoke-Expression "ffmpeg.exe -i '$($_.FullName)'  $paramStr  '$($newfullname)'"
    # ffmpeg.exe -i $_.FullName  $paramStr  ($_.FullName.Substring(0,$_.FullName.Length-4)+'.webp')

    if ((Test-Path -LiteralPath $newfullname)-and (-not $noDelete)){
        rm -LiteralPath $_.FullName
        Write-Host -ForegroundColor yellow "delete $($_.FullName) complete "
     $count++
     }
     else{
        Write-Host -ForegroundColor red "not find the source file or no delete "
        #break
     }
    }
}

Write-Host -ForegroundColor  Green   "compress $count  png files  complete"





