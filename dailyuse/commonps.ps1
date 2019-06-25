##############################################################################
#.SYNOPSIS
# get a formated length of file , ����ֵ����1024����ø���ĵ�λ��ֱ��GB
#
#.DESCRIPTION
# ��ø�ʽ�����ļ���С�ַ���
#
#.PARAMETER TypeName
# ��ֵ����
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
# ���һ��������Ҫ���ٶ�����λ����ʾ
#
#.PARAMETER number
#���������
#
#.EXAMPLE
#  
##############################################################################
function Get-NeedBinaryDigits($number){
# ����powershell���������־���int64,2����62λ��ʱ�������ˣ��������Ƚϵ�2����61λ��Ҳ����2��62�η���2��63�η��ͻ����int64
# int64 ��64λ������һλ�Ƿ���λ�� ���Ա������������ 2��63�η�-1�����λ�±���63��
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


