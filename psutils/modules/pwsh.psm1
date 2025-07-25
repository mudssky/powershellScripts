function Out-ModuleToFile {
    <#
.SYNOPSIS
    保存当前会话加载的指定模块的所有函数到指定文件。

.DESCRIPTION
    此函数用于将PowerShell会话中已加载的特定模块的所有函数定义提取出来，并保存到一个.psm1文件中。
    这对于创建模块的精简版本、备份函数定义或进行代码分析非常有用。

.PARAMETER ModuleName
    要保存函数的模块名称，默认为 'psutils'。

.PARAMETER ModuleOutputDirectory
    保存输出文件的目录，默认为当前目录 '.'。

.PARAMETER ModuleOutputName
    输出文件的名称。如果未指定，将默认为 '<ModuleName>.psm1'。

.OUTPUTS
    无。函数将函数定义写入到指定的文件中。

.EXAMPLE
    Save-ModuleFunctionsToFile -ModuleName "MyModule" -ModuleOutputDirectory "C:\Temp"
    将 "MyModule" 模块的所有函数保存到 C:\Temp\MyModule.psm1 文件中。

.EXAMPLE
    Save-ModuleFunctionsToFile -ModuleName "UtilityFunctions" -ModuleOutputName "CustomUtils.psm1"
    将 "UtilityFunctions" 模块的函数保存到名为 "CustomUtils.psm1" 的文件中。

.NOTES
    此函数仅保存函数定义，不包括模块清单文件（.psd1）或其他模块资源。
    它依赖于当前会话中模块的加载状态。
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

Export-ModuleMember -Function Out-ModuleToFile