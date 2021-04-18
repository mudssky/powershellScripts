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
function Get-FormatLength($length){
    if ($length -gt 1gb){
       return  "$( "{0:f2}" -f  $length/1gb)GB"
    }elseif ($length -gt 1mb){
          return  "$( "{0:f2}" -f  $length/1mb)MB"
    }elseif ($length -gt 1kb)
    {
        return  "$( "{0:f2}" -f  $length/1kb)KB"
    }else{
         return "$length B"
    }    
}



##############################################################################
#.SYNOPSIS
# get needed digits to represent a decimal number
#
#.DESCRIPTION
# 获得一个数字需要多少二进制位来表示
#
#.PARAMETER number
#输入的数字
#
#.EXAMPLE
#  
##############################################################################
function Get-NeedBinaryDigits($number){
# 由于powershell中最大的数字就是int64,2左移62位的时候就溢出了，所以最大比较到2左移61位。也就是2的62次方，2的63次方就会溢出int64
# int64 有64位，其中一位是符号位， 所以表达的最大数就是 2的63次方-1（最高位下标是63）
    if ($number -gt ([int64]::MaxValue)){
        Write-Host -ForegroundColor Red "the number is exceed the area of int64"
    }else{
        for($i=62;$i -gt 0;$i-=1){
            if( ([int64](1) -shl $i) -lt $number){
                return ($i+1)
            }
        }
    }
}

<#
.SYNOPSIS
    获取一个和输入哈希表key和value调换位置的哈希表
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> Get-ReversedMap -inputMap $xxxMap
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
function Get-ReversedMap() {
    param (
        $inputMap
    )
    $reversedMap = @{}
    foreach ($key in $inputMap.Keys) {
        $reversedMap[$inputMap[$key]]=$key
    }
    return $reversedMap
}


