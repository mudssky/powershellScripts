<#
.example
downBiliBiliLinksFromClipboard.ps1 -needDanmuku
#>
param(
[switch]$needDanmuku
)

$str = Get-Clipboard;
# $str.Split('') | foreach{$_; annie -C -p $_}
if ($needDanmuku){
$str.Split('') | foreach{$_; annie -C -p $_}
}else{
$str.Split('') | foreach{$_; annie -p $_}
}

