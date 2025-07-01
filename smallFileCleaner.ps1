<#
.SYNOPSIS
    小文件清理脚本

.DESCRIPTION
    该脚本用于查找并清理当前目录下小于指定大小的文件。
    可以选择只列出文件而不删除，或者直接删除小于阈值的文件。
    支持自定义文件大小阈值，默认为10KB。

.PARAMETER limitedSize
    文件大小阈值，小于此大小的文件将被处理，默认为10KB

.PARAMETER noDelete
    开关参数，如果指定则只列出符合条件的文件而不删除

.EXAMPLE
    .\smallFileCleaner.ps1 -limitedSize 10kb
    删除当前目录下小于10KB的文件

.EXAMPLE
    .\smallFileCleaner.ps1 -limitedSize 5kb -noDelete
    列出当前目录下小于5KB的文件但不删除

.EXAMPLE
    .\smallFileCleaner.ps1 -limitedSize 1mb
    删除当前目录下小于1MB的文件

.NOTES
    支持KB、MB、GB等单位
    提供格式化的文件大小显示
    默认处理当前目录下的所有文件
#>
param(
    [int]$limitedSize = 10kb,
    [switch] $noDelete = $false

)

##############################################################################
#.SYNOPSIS
# get a formated length of file , 当数值超过1024会采用更大的单位，直到GB
#
#.DESCRIPTION
# 获得格式化的文件大小字符串
#
#.PARAMETER TypeName
# 数值类型
#
#.PARAMETER ComObject
# 
#
#.PARAMETER Force
# 
#
#.EXAMPLE
#  
##############################################################################
function Get-FormatLength($length) {
    if ($length -gt 1gb) {
        return  "$( "{0:f2}" -f  $length/1gb)GB"
    }
    elseif ($length -gt 1mb) {
        return  "$( "{0:f2}" -f  $length/1mb)MB"
    }
    elseif ($length -gt 1kb) {
        return  "$( "{0:f2}" -f  $length/1kb)KB"
    }
    else {
        return "$length B"
    }    

}

# 清理小于 100kb的小文件
$count = 0; 
Get-ChildItem -Recurse -File | ForEach-Object { if ($_.Length -lt $limitedSize) {
        if ($noDelete) {
            Write-Output -ForegroundColor Yellow "$($_.FullName),$("{0:f2}" -f ($_.Length/1kb))kb"
        }
        else {
            Remove-Item -Force -LiteralPath  $_.FullName;
            $count += 1;
            "$count,deleted $($_.FullName)"
        }
    } };
Write-Host -ForegroundColor Green " delete smaller than $( Get-FormatLength($limitedSize)) file counts: $count "

