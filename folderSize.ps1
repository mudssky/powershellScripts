param(
	[string]$path = '.'
)
$count = 0;
$folderSize = 0;
Get-ChildItem -Recurse -Path $path |   ForEach-Object { $folderSize += $_.length; $count += 1 }

Write-Host -ForegroundColor Green ('共扫描文件数：{0},总文件大小{1:n3}GB,path:{2}' -f $count, ($folderSize / 1gb), $path)
