# 错误处理相关方法


function Debug-CommandExecution {
    <#
    .SYNOPSIS
        输出上调命令执行成功或失败的信息，可以用于调试程序，或者在程序出错时提供更多提示信息
    .DESCRIPTION
        A longer description of the function, its purpose, common use cases, etc.
    .NOTES
        Information or caveats about the function e.g. 'This function is not supported in Linux'
    .LINK
        Specify a URI to a help page, this will show when Get-Help -Online is used.
    .EXAMPLE
        Test-MyTestFunction -Verbose
        Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    #>
    
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$CommandName
    )

    if (-not $?) {
        # 输出执行失败信息
        Write-Host -ForegroundColor Red  ("Check-CommandExecution: {0} execute failed" -f $CommandName)
        throw ("{0} error found" -f $CommandName)
    }
    else {
        # 上条命令执行成功后输出消息
        Write-Host -ForegroundColor Green  ("Check-CommandExecution: {0} execute successful" -f $CommandName)
    }
}


Export-ModuleMember -Function *