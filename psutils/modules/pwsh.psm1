function Out-ModuleToFile {
    <#
    .SYNOPSIS
        保存当前会话加载的指定模块的所有函数，到指定的文件。
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
        [string]
        $ModuleName = 'psutils',
        [string]
        $ModuleOutputDirectory = '.',
        [string]
        $ModuleOutputName = ''
    )

    if (-not $ModuleOutputName) {
        $ModuleOutputName = $ModuleName + '.psm1'
    }



    $functions = Get-Command -Module $ModuleName -CommandType Function

    $outputFunctions = New-Object System.Collections.Generic.List[string]
    foreach ($function in $functions) {
        $fullFunction = 'function ' + $function.Name + '{' + "`n" + $function.Definition + "`n" + '}'
        $outputFunctions.Add($fullFunction)
    }


    Out-File -FilePath $ModuleOutputName -InputObject ($outputFunctions -Join "`n`n") -Encoding utf8
}