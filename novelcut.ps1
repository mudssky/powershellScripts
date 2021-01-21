param(
#default cut filter for huawei m6 10.8
#'2032:1440:264:0' pc  2560*1440 fullscreen cut
[string]$cropstr= 'default',
[switch]$lossless=$false
)
#webpCompress.ps1 -paramStr '-vf crop="2000:1440:280:0"' -targetPath '.\фад╩╫ьм╪(98).png' -lossless -limitSize 0 -noDelete
$cropdict=@{
'default'='-vf crop="1600:2132:0:244"';
'1'='-vf crop="2028:1440:266:0"'
'2'='-vf crop="1836:1440:362:0"'
'3'='-vf crop="1014:1440:774:0"'
'4'='-vf crop="2000:1440:280:0"'
}
$paramStr = $cropdict[$cropstr]
echo $paramStr
if($lossless){
    ls *.png,*.jpg | %{webpCompress.ps1 -paramStr $paramStr -targetPath $_.Name -lossless -limitSize 0 }

}else{
    ls *.png,*.jpg | %{webpCompress.ps1 -paramStr $paramStr -targetPath $_.Name  -limitSize 0 }
}
rm *.jpg,*.png