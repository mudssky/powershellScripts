[CmdletBinding(SupportsShouldProcess)]
param(
    #default cut filter for huawei m6 10.8
    #'2032:1440:264:0' pc  2560*1440 fullscreen cut
    [string]$cropstr = 'default',
    [switch]$lossless = $false,
    [switch]$Recurse = $false
)
#webpCompress.ps1 -paramStr '-vf crop="2000:1440:280:0"' -targetPath '.\��Ļ��ͼ(98).png' -lossless -limitSize 0 -noDelete
$cropdict = @{
    'default'          = '-vf crop="1600:2180:0:190"';
    'default-huaweim6' = '-vf crop="1600:2132:0:244"';
    '1'                = '-vf crop="2028:1440:266:0"'
    '2'                = '-vf crop="1836:1440:362:0"'
    '3'                = '-vf crop="1014:1440:774:0"'
    '4'                = '-vf crop="2000:1440:280:0"'
}
$paramStr = $cropdict[$cropstr]
Write-Output $paramStr

Get-ChildItem -Recurse:$Recurse  *.png, *.jpg | ForEach-Object { webpCompress.ps1 -paramStr $paramStr -targetPath $_.FullName -lossless:$lossless -limitSize 0 }


Remove-Item *.jpg, *.png