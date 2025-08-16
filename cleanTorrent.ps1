<#
.SYNOPSIS
    清理.url文件的脚本

.DESCRIPTION
    该脚本递归搜索当前目录及其子目录，查找并删除所有.url文件。
    .url文件通常是Windows快捷方式文件，在某些下载场景中可能产生大量此类文件。
    脚本会显示删除的文件路径和总计数。

.EXAMPLE
    .\cleanTorrent.ps1
    清理当前目录及子目录下的所有.url文件

.NOTES
    脚本会递归处理所有子目录
    删除操作不可逆，请谨慎使用
    执行完成后会暂停等待用户确认
    显示清理的文件路径和总数统计
#>
$num = 0; Get-ChildItem -Force -Recurse | ForEach-Object { $num++; if ($_.Name.EndsWith('.torrent')) { "clean : $($_.FullName)"; Remove-Item -Force -LiteralPath $_.FullName } } ; "fileCounts:$num"
$urlnum = 0; Get-ChildItem -Force -Recurse | ForEach-Object { $num++; if ($_.Name.EndsWith('.url')) { "clean : $($_.FullName)"; Remove-Item -Force -LiteralPath $_.FullName } } ; "fileCounts:$urlnum"; Pause