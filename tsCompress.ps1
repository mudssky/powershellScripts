<#
.example
tsCompress.ps1 -deleteSourceFile -paramStr '-vcodec libx264 -crf 23  -preset veryfast  -acodec copy'
��Ŀ��Ŀ¼��ִ�оͻ�ݹ����¼�Ƶ�flv��ts�ļ�����ѹ�ơ�
paramStrָ��ffmepgѹ�ƵĲ���
deleteSourceFileѡ����ϣ��Ϳ����Զ�ɾ��Դ�ļ���

#>


param(
[string]$paramStr='-vcodec hevc -crf 23  -preset slow  -acodec copy ',
[string]$targetPath='.',
[switch]$deleteSourceFile
)


$tsList = ls  -Recurse -LiteralPath $($targetPath) | where{($_.Extension -eq '.flv') -or ($_.Extension -eq '.ts') }

$tsList | foreach{
$oldName =  $_.FullName
$extLength = $_.Extension.Length
$newName = $oldName.Substring(0,$oldName.length-$extLength)+'.mp4'
$excuteStr = "ffmpeg -i '$($oldName)'  $paramStr '$($newName)' "
Write-Host -ForegroundColor Green ('[compress]'+$excuteStr)
Invoke-Expression $excuteStr

if ($deleteSourceFile){
    rm -LiteralPath $oldName
}
Write-Host -ForegroundColor Yellow "deleteSourceFile completed�� $oldName"
}


