
param(
    # [string]$path
    [string]$wildcard,
    [string]$outPath,
    [switch]$delete,
    [switch]$whatif

)
trap {
    "error found"
}
$xmlList = Get-ChildItem $wildcard | ? { $_.Extension -eq '.xml' } 

if ($whatif) {
    Write-Host -ForegroundColor Green 'there are files to be concat'
    $xmlList
    exit 0
}
if ($xmlList.Length -gt 1) {
    if (-not $outPath) {
        $fileName = $xmlList[0].Name
        $outPath = $fileName.Substring(0, $fileName.Length - 4) + '_concat.xml'
    }
    [xml]$biliXml = Get-Content -Path $xmlList[0]
    $biliXmlStr = $biliXml.OuterXml
    $firstXmlStr = $biliXmlStr.Substring(0, $biliXmlStr.Length - 4)
    for ($i = 1; $i -lt $xmlList.Length; $i++) {
        [xml]$currentXml = Get-Content $xmlList[$i]
        if ($currentXml.OuterXml -match '/BililiveRecorderXmlStyle>([\s\S]*?)</i>$') {
            $firstXmlStr += $Matches[1]
            Write-Host -ForegroundColor Green ('No {0} matched success' -f $i)
        }
    }
    $firstXmlStr += '</i>'
    Out-File -InputObject $firstXmlStr -FilePath $outPath
    if ($delete) {
        $xmlList | % { rm $_ }
    }
}
else {
    Write-Host -ForegroundColor Green 'there is only one matched xml,no need to concat'
}

# [xml]$biliXml = Get-Content -Path '20210531-225728 【B限直播】6000人纪念【新人VUP】 自录.xml' 
# $biliXmlStr = $biliXml.OuterXml
# $firstXmlStr = $biliXmlStr.Substring(0, $biliXmlStr.Length - 4)
# $firstXmlStr

# $biliXmlStr -match 'BililiveRecorderXmlStyle`/>([\s\S]*?)<`/i'
# $biliXmlStr -match '/BililiveRecorderXmlStyle>([\s\S]*?)</i>$'
# $Matches[1]
