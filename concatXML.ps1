
<#
.SYNOPSIS
    XML文件合并脚本

.DESCRIPTION
    该脚本用于将多个XML文件合并为一个文件。支持通配符匹配、预览模式和删除源文件等功能。
    脚本会检查匹配的文件数量，只有在找到多个XML文件时才执行合并操作。

.PARAMETER wildcard
    用于匹配XML文件的通配符模式

.PARAMETER outPath
    输出合并后XML文件的路径

.PARAMETER delete
    开关参数，如果指定则在合并完成后删除源XML文件

.PARAMETER whatif
    开关参数，如果指定则只显示将要合并的文件列表，不执行实际合并操作

.EXAMPLE
    .\concatXML.ps1 -wildcard "*.xml" -outPath "merged.xml"
    合并当前目录下的所有XML文件为merged.xml

.EXAMPLE
    .\concatXML.ps1 -wildcard "data*.xml" -outPath "result.xml" -delete
    合并匹配data*.xml模式的文件并删除源文件

.EXAMPLE
    .\concatXML.ps1 -wildcard "*.xml" -whatif
    预览将要合并的XML文件列表

.NOTES
    只处理扩展名为.xml的文件
    包含错误处理机制
    至少需要2个或以上的XML文件才会执行合并
#>
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
$xmlList = Get-ChildItem $wildcard | Where-Object { $_.Extension -eq '.xml' } 

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
        $xmlList | ForEach-Object { Remove-Item $_ }
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
