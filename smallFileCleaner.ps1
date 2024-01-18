<#
.synopsis
smallFileCleaner.ps1 -limitedSize 10kb
清理小于limitedSize的文件，默认limitedSize值为10kb
-noDelete 不删除文件，只列出文件
.example
smallFileCleaner.ps1 -limitedSize 10kb
清理小于limitedSize的文件
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

