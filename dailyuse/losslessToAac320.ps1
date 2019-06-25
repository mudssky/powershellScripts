# 解决mv报错问题，因为路径名中包含的[]方括号会被PowerShell解析，路径操作时加上-LiteralPath可以解决这一问题
# 删除和ls遍历的时候，不加-Force选项会导致.*格式的隐藏文件无法被遍历或者删除
# replace 替换如果路径名中包含.aac会出问题，所以这里直接，替换文件末尾了。
ls -Recurse -File  *.wav,*.flac | foreach{ $num++;ffmpeg -i $_.FullName -b:a 320k ($_.FullName.Substring(0,$_.FullName.Length-$_.Extension.Length)+'.aac');rm -Force -LiteralPath $_.FullName; "convert and deleted: $($_.Fullname)"};"lossless counts:$num";pause