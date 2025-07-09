<#
.SYNOPSIS
    增强的模块内帮助搜索工具

.DESCRIPTION
    提供快速搜索指定模块或路径中PowerShell函数和脚本帮助信息的功能，
    结合Get-Help的标准化和自定义解析的性能优势，支持.psm1和.ps1文件。

.NOTES
    作者: mudssky
    版本: 2.0.0
    创建日期: 2024
    更新: 添加Get-Help支持和ps1脚本支持
#>

<#
.SYNOPSIS
    搜索指定模块或路径中的函数和脚本帮助信息

.DESCRIPTION
    在指定的模块路径中搜索PowerShell函数和脚本，并提取其帮助信息。
    支持按函数名、描述内容进行模糊搜索，可选择使用Get-Help或自定义解析。
    支持.psm1模块文件和.ps1脚本文件。

.PARAMETER SearchTerm
    搜索关键词，支持函数名或描述内容的模糊匹配

.PARAMETER ModulePath
    要搜索的模块路径，默认为当前psutils模块路径

.PARAMETER FunctionName
    精确搜索指定的函数名

.PARAMETER ShowDetails
    是否显示详细的帮助信息，包括参数说明和示例

.PARAMETER UseGetHelp
    是否使用Get-Help获取帮助信息（需要先导入模块）

.PARAMETER IncludeScripts
    是否包含.ps1脚本文件的搜索

.PARAMETER IncludePrivate
    是否包含私有函数（未导出的函数）

.EXAMPLE
    Search-ModuleHelp -SearchTerm "install"
    搜索包含"install"关键词的函数

.EXAMPLE
    Search-ModuleHelp -FunctionName "Get-OperatingSystem" -ShowDetails -UseGetHelp
    使用Get-Help精确搜索Get-OperatingSystem函数并显示详细信息

.EXAMPLE
    Search-ModuleHelp -ModulePath "C:\MyModule" -SearchTerm "config" -IncludeScripts
    在指定路径中搜索包含"config"的函数和脚本

.OUTPUTS
    [PSCustomObject[]] 包含函数信息的对象数组

.NOTES
    此函数支持两种模式：
    1. 自定义解析模式（默认）：直接解析文件，性能更好
    2. Get-Help模式：使用标准Get-Help，信息更准确但需要导入模块
#>
function Search-ModuleHelp {
    [CmdletBinding(DefaultParameterSetName = 'SearchTerm')]
    param(
        [Parameter(ParameterSetName = 'SearchTerm', Position = 0)]
        [string]$SearchTerm,
        
        [Parameter()]
        [string]$ModulePath = $PSScriptRoot,
        
        [Parameter(ParameterSetName = 'FunctionName')]
        [string]$FunctionName,
        
        [Parameter()]
        [switch]$ShowDetails,
        
        [Parameter()]
        [switch]$UseGetHelp,
        
        [Parameter()]
        [switch]$IncludeScripts,
        
        [Parameter()]
        [switch]$IncludePrivate
    )
    
    begin {
        Write-Verbose "开始搜索模块帮助信息..."
        Write-Verbose "搜索路径: $ModulePath"
        Write-Verbose "使用Get-Help: $UseGetHelp"
        Write-Verbose "包含脚本: $IncludeScripts"
        
        # 验证路径是否存在
        if (-not (Test-Path $ModulePath)) {
            Write-Error "指定的模块路径不存在: $ModulePath"
            return
        }
        
        $results = @()
        $loadedModules = @()
    }
    
    process {
        try {
            # 确定要搜索的文件类型
            $fileFilters = @('*.psm1')
            if ($IncludeScripts) {
                $fileFilters += '*.ps1'
            }
            
            # 获取所有相关文件
            $allFiles = @()
            foreach ($filter in $fileFilters) {
                $allFiles += Get-ChildItem -Path $ModulePath -Filter $filter -Recurse
            }
            
            if ($UseGetHelp) {
                # 使用Get-Help模式
                $searchResults = Search-WithGetHelp -Files $allFiles -SearchTerm $SearchTerm -FunctionName $FunctionName -ShowDetails:$ShowDetails
                if ($searchResults) {
                    $results += $searchResults
                }
            }
            else {
                # 使用自定义解析模式
                $searchResults = Search-WithCustomParsing -Files $allFiles -SearchTerm $SearchTerm -FunctionName $FunctionName -ShowDetails:$ShowDetails
                if ($searchResults) {
                    $results += $searchResults
                }
            }
        }
        catch {
            Write-Error "搜索过程中发生错误: $($_.Exception.Message)"
        }
    }
    
    end {
        # 清理临时导入的模块
        foreach ($module in $loadedModules) {
            try {
                Remove-Module $module -Force -ErrorAction SilentlyContinue
                Write-Verbose "已清理临时模块: $module"
            }
            catch {
                Write-Verbose "清理模块失败: $module - $($_.Exception.Message)"
            }
        }
        
        # 输出结果
        if ($results.Count -eq 0) {
            Write-Warning "未找到匹配的函数或脚本"
            return
        }
        
        # 只返回结果，不显示格式化输出
        return $results
    }
}

<#
.SYNOPSIS
    使用 Get-Help 方式搜索帮助信息。

.DESCRIPTION
    此内部函数通过临时导入 PowerShell 模块或脚本文件，并利用标准的 `Get-Help` cmdlet 来获取函数的帮助信息。
    它旨在为 `Search-ModuleHelp` 函数提供一个基于 `Get-Help` 的搜索后端，以确保获取到的帮助信息是标准化且准确的。
    函数会处理 `.psm1` 模块文件和 `.ps1` 脚本文件，并根据提供的搜索条件进行过滤。

.PARAMETER Files
    必需参数。一个 `System.IO.FileInfo` 数组，包含要搜索的模块或脚本文件。

.PARAMETER SearchTerm
    可选参数。用于模糊匹配函数名称、概要或描述的关键词。如果指定，结果将根据此关键词进行过滤。

.PARAMETER FunctionName
    可选参数。用于精确匹配的函数名称。如果指定，将只返回与此名称完全匹配的函数帮助信息。

.PARAMETER ShowDetails
    可选参数。一个开关参数，指示是否显示详细的帮助信息。此参数主要用于控制输出的详细程度。

.OUTPUTS
    [PSCustomObject[]] 返回一个包含帮助信息的自定义对象数组，每个对象代表一个函数的帮助条目。

.EXAMPLE
    # 内部调用示例，通常不直接由用户调用
    $files = Get-ChildItem -Path "./modules" -Filter "*.psm1"
    Search-WithGetHelp -Files $files -SearchTerm "install" -ShowDetails
    # 搜索包含 "install" 关键词的函数帮助信息，并显示详细信息。

.NOTES
    此函数是 `Search-ModuleHelp` 的内部辅助函数，不建议直接调用。
    它会临时导入模块，并在完成后尝试清理导入的模块。
    对于 `.ps1` 脚本文件，它会尝试将其作为模块导入以获取帮助信息。
    在处理大型模块或大量文件时，临时导入可能会对性能产生一定影响。

#>
function Search-WithGetHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$Files,
        
        [Parameter()]
        [string]$SearchTerm,
        
        [Parameter()]
        [string]$FunctionName,
        
        [Parameter()]
        [switch]$ShowDetails
    )
    
    $results = @()
    $tempModules = @()
    
    foreach ($file in $Files) {
        try {
            Write-Verbose "正在处理文件: $($file.Name)"
            
            # 根据文件类型处理
            if ($file.Extension -eq '.psm1') {
                # 处理模块文件
                $tempModuleName = "TempModule_$([System.Guid]::NewGuid().ToString('N')[0..7] -join '')"
                
                try {
                    # 临时导入模块
                    Import-Module $file.FullName -Name $tempModuleName -Force -Global -ErrorAction Stop
                    $tempModules += $tempModuleName
                    
                    # 获取模块中的函数
                    $functions = Get-Command -Module $tempModuleName -CommandType Function -ErrorAction SilentlyContinue
                    
                    foreach ($func in $functions) {
                        # 应用搜索过滤器
                        $shouldInclude = $false
                        
                        if ($FunctionName) {
                            $shouldInclude = $func.Name -eq $FunctionName
                        }
                        elseif ($SearchTerm) {
                            $shouldInclude = $func.Name -like "*$SearchTerm*"
                        }
                        else {
                            $shouldInclude = $true
                        }
                        
                        if ($shouldInclude) {
                            # 使用Get-Help获取帮助信息
                            $helpInfo = Get-Help $func.Name -ErrorAction SilentlyContinue
                            
                            if ($helpInfo) {
                                $result = Convert-GetHelpToCustomObject -HelpInfo $helpInfo -FilePath $file.FullName -Type "Function"
                                
                                # 如果有搜索词，进一步过滤描述内容
                                if ($SearchTerm -and -not [string]::IsNullOrEmpty($SearchTerm)) {
                                    if (($result.Synopsis -like "*$SearchTerm*") -or ($result.Description -like "*$SearchTerm*")) {
                                        $results += $result
                                    }
                                }
                                else {
                                    $results += $result
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "无法导入模块 $($file.Name): $($_.Exception.Message)"
                    continue
                }
            }
            elseif ($file.Extension -eq '.ps1') {
                # 处理脚本文件
                $scriptHelp = Get-Help $file.FullName -ErrorAction SilentlyContinue
                
                if ($scriptHelp) {
                    $shouldInclude = $false
                    
                    if ($FunctionName) {
                        $shouldInclude = $file.BaseName -eq $FunctionName
                    }
                    elseif ($SearchTerm) {
                        $shouldInclude = ($file.BaseName -like "*$SearchTerm*") -or 
                        ($scriptHelp.Synopsis -like "*$SearchTerm*") -or 
                        ($scriptHelp.Description -like "*$SearchTerm*")
                    }
                    else {
                        $shouldInclude = $true
                    }
                    
                    if ($shouldInclude) {
                        $result = Convert-GetHelpToCustomObject -HelpInfo $scriptHelp -FilePath $file.FullName -Type "Script"
                        $results += $result
                    }
                }
            }
        }
        catch {
            Write-Verbose "处理文件 $($file.Name) 时出错: $($_.Exception.Message)"
        }
    }
    
    # 清理临时模块
    foreach ($tempModule in $tempModules) {
        try {
            Remove-Module $tempModule -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "清理临时模块失败: $tempModule"
        }
    }
    
    return $results
}

<#
.SYNOPSIS
    使用自定义解析方式搜索帮助信息。

.DESCRIPTION
    此内部函数通过直接解析 PowerShell 模块或脚本文件的内容来提取帮助信息，而不需要临时导入模块。
    它旨在为 `Search-ModuleHelp` 函数提供一个高性能的搜索后端，特别适合处理大量文件或需要快速搜索的场景。
    虽然性能更好，但提取的帮助信息可能不如 `Get-Help` 获取的标准帮助信息准确。

.PARAMETER Files
    必需参数。一个 `System.IO.FileInfo` 数组，包含要搜索的模块或脚本文件。

.PARAMETER SearchTerm
    可选参数。用于模糊匹配函数名称、概要或描述的关键词。如果指定，结果将根据此关键词进行过滤。

.PARAMETER FunctionName
    可选参数。用于精确匹配的函数名称。如果指定，将只返回与此名称完全匹配的函数帮助信息。

.PARAMETER ShowDetails
    可选参数。一个开关参数，指示是否显示详细的帮助信息。此参数主要用于控制输出的详细程度。

.OUTPUTS
    [PSCustomObject[]] 返回一个包含帮助信息的自定义对象数组，每个对象代表一个函数的帮助条目。

.EXAMPLE
    # 内部调用示例，通常不直接由用户调用
    $files = Get-ChildItem -Path "./modules" -Filter "*.psm1"
    Search-WithCustomParsing -Files $files -SearchTerm "config" -ShowDetails
    # 搜索包含 "config" 关键词的函数帮助信息，并显示详细信息。

.NOTES
    此函数是 `Search-ModuleHelp` 的内部辅助函数，不建议直接调用。
    它通过正则表达式直接解析文件内容来提取帮助信息，因此性能较高但可能不够准确。
    对于 `.ps1` 脚本文件，它会尝试解析文件顶部的注释块作为帮助信息。
    在处理大型文件时，此方法比 `Get-Help` 方式更高效，但可能无法获取完整的参数信息。
#>
function Search-WithCustomParsing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$Files,
        
        [Parameter()]
        [string]$SearchTerm,
        
        [Parameter()]
        [string]$FunctionName,
        
        [Parameter()]
        [switch]$ShowDetails
    )
    
    $results = @()
    
    foreach ($file in $Files) {
        Write-Verbose "正在解析文件: $($file.Name)"
        
        # 读取文件内容
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        
        # 检查文件内容是否为空
        if ([string]::IsNullOrEmpty($content)) {
            Write-Verbose "文件 $($file.Name) 为空，跳过处理"
            continue
        }
        
        if ($file.Extension -eq '.psm1') {
            # 处理模块文件中的函数
            $results += Parse-ModuleFunctions -Content $content -FilePath $file.FullName -SearchTerm $SearchTerm -FunctionName $FunctionName
        }
        elseif ($file.Extension -eq '.ps1') {
            # 处理脚本文件
            $results += Parse-ScriptHelp -Content $content -FilePath $file.FullName -SearchTerm $SearchTerm -FunctionName $FunctionName
        }
    }
    
    return $results
}

<#
.SYNOPSIS
    解析模块文件中的函数

.DESCRIPTION
    从模块文件内容中提取函数定义和帮助信息
#>
function Parse-ModuleFunctions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter()]
        [string]$SearchTerm,
        
        [Parameter()]
        [string]$FunctionName
    )
    
    $results = @()
    $foundFunctionNames = @()
    
    # 模式1: 帮助注释在函数外部（传统模式）
    $externalHelpPattern = '(?s)<#([\s\S]*?)#>[\s\r\n]*function\s+([\w-]+)\s*\{?'
    $externalMatches = [regex]::Matches($Content, $externalHelpPattern)
    
    foreach ($match in $externalMatches) {
        $helpBlock = $match.Groups[1].Value.Trim()
        $funcName = $match.Groups[2].Value.Trim()
        $foundFunctionNames += $funcName
        
        # 解析帮助信息
        $helpInfo = Parse-HelpBlock -HelpBlock $helpBlock -Name $funcName -FilePath $FilePath -Type "Function"
        
        # 应用搜索过滤器
        $shouldInclude = $false
        
        if ($FunctionName) {
            $shouldInclude = $funcName -eq $FunctionName
        }
        elseif ($SearchTerm) {
            $shouldInclude = ($funcName -like "*$SearchTerm*") -or 
            ($helpInfo.Synopsis -like "*$SearchTerm*") -or 
            ($helpInfo.Description -like "*$SearchTerm*")
        }
        else {
            $shouldInclude = $true
        }
        
        if ($shouldInclude) {
            $results += $helpInfo
        }
    }
    
    # 模式2: 帮助注释在函数内部
    $internalHelpPattern = '(?s)function\s+([\w-]+)\s*\{[\s\r\n]*<#([\s\S]*?)#>'
    $internalMatches = [regex]::Matches($Content, $internalHelpPattern)
    
    foreach ($match in $internalMatches) {
        $funcName = $match.Groups[1].Value.Trim()
        $helpBlock = $match.Groups[2].Value.Trim()
        
        # 如果这个函数还没有被外部帮助模式匹配到
        if ($funcName -notin $foundFunctionNames) {
            $foundFunctionNames += $funcName
            
            # 解析帮助信息
            $helpInfo = Parse-HelpBlock -HelpBlock $helpBlock -Name $funcName -FilePath $FilePath -Type "Function"
            
            # 应用搜索过滤器
            $shouldInclude = $false
            
            if ($FunctionName) {
                $shouldInclude = $funcName -eq $FunctionName
            }
            elseif ($SearchTerm) {
                $shouldInclude = ($funcName -like "*$SearchTerm*") -or 
                ($helpInfo.Synopsis -like "*$SearchTerm*") -or 
                ($helpInfo.Description -like "*$SearchTerm*")
            }
            else {
                $shouldInclude = $true
            }
            
            if ($shouldInclude) {
                $results += $helpInfo
            }
        }
    }
    
    # 如果没有找到带帮助注释的函数，尝试查找简单的函数定义
    if ($foundFunctionNames.Count -eq 0) {
        $simpleFunctionPattern = '(?m)^\s*function\s+([\w-]+)\s*\{?'
        $simpleMatches = [regex]::Matches($Content, $simpleFunctionPattern)
        
        foreach ($match in $simpleMatches) {
            $funcName = $match.Groups[1].Value.Trim()
            
            # 应用搜索过滤器
            $shouldInclude = $false
            
            if ($FunctionName) {
                $shouldInclude = $funcName -eq $FunctionName
            }
            elseif ($SearchTerm) {
                $shouldInclude = $funcName -like "*$SearchTerm*"
            }
            else {
                $shouldInclude = $true
            }
            
            if ($shouldInclude) {
                $helpInfo = [PSCustomObject]@{
                    Name        = $funcName
                    Type        = "Function"
                    Synopsis    = "无帮助信息"
                    Description = "无帮助信息"
                    Parameters  = @()
                    Examples    = @()
                    FilePath    = $FilePath
                    ModuleName  = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
                }
                $results += $helpInfo
            }
        }
    }
    # 如果找到了带帮助注释的函数，还需要查找没有帮助注释的简单函数
    else {
        # $foundFunctionNames 已经在上面填充了
        
        # 查找所有函数定义
        $allFunctionPattern = '(?m)^\s*function\s+([\w-]+)\s*\{?'
        $allMatches = [regex]::Matches($Content, $allFunctionPattern)
        
        foreach ($match in $allMatches) {
            $funcName = $match.Groups[1].Value.Trim()
            
            # 如果这个函数没有帮助注释，添加基本信息
            if ($funcName -notin $foundFunctionNames) {
                # 应用搜索过滤器
                $shouldInclude = $false
                
                if ($FunctionName) {
                    $shouldInclude = $funcName -eq $FunctionName
                }
                elseif ($SearchTerm) {
                    $shouldInclude = $funcName -like "*$SearchTerm*"
                }
                else {
                    $shouldInclude = $true
                }
                
                if ($shouldInclude) {
                    $helpInfo = [PSCustomObject]@{
                        Name        = $funcName
                        Type        = "Function"
                        Synopsis    = "无帮助信息"
                        Description = "无帮助信息"
                        Parameters  = @()
                        Examples    = @()
                        FilePath    = $FilePath
                        ModuleName  = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
                    }
                    $results += $helpInfo
                }
            }
        }
    }
    
    return $results
}

<#
.SYNOPSIS
    解析脚本文件的帮助信息

.DESCRIPTION
    从脚本文件内容中提取帮助信息
#>
function Parse-ScriptHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter()]
        [string]$SearchTerm,
        
        [Parameter()]
        [string]$FunctionName
    )
    
    $results = @()
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    
    # 应用搜索过滤器
    $shouldInclude = $false
    
    if ($FunctionName) {
        $shouldInclude = $scriptName -eq $FunctionName
    }
    elseif ($SearchTerm) {
        $shouldInclude = $scriptName -like "*$SearchTerm*"
    }
    else {
        $shouldInclude = $true
    }
    
    if (-not $shouldInclude) {
        return $results
    }
    
    # 查找脚本级别的帮助注释
    $scriptHelpPattern = '(?s)^\s*<#([\s\S]*?)#>'
    $helpMatch = [regex]::Match($Content, $scriptHelpPattern)
    
    if ($helpMatch.Success) {
        $helpBlock = $helpMatch.Groups[1].Value.Trim()
        $helpInfo = Parse-HelpBlock -HelpBlock $helpBlock -Name $scriptName -FilePath $FilePath -Type "Script"
        
        # 如果有搜索词，进一步过滤描述内容
        if ($SearchTerm -and -not [string]::IsNullOrEmpty($SearchTerm)) {
            if (($helpInfo.Synopsis -like "*$SearchTerm*") -or ($helpInfo.Description -like "*$SearchTerm*")) {
                $results += $helpInfo
            }
        }
        else {
            $results += $helpInfo
        }
    }
    else {
        # 没有找到帮助注释，创建基本信息
        $helpInfo = [PSCustomObject]@{
            Name        = $scriptName
            Type        = "Script"
            Synopsis    = "无帮助信息"
            Description = "无帮助信息"
            Parameters  = @()
            Examples    = @()
            FilePath    = $FilePath
            ModuleName  = "Script"
        }
        $results += $helpInfo
    }
    
    return $results
}

<#
.SYNOPSIS
    将Get-Help结果转换为自定义对象

.DESCRIPTION
    将Get-Help返回的帮助信息转换为统一的自定义对象格式

.PARAMETER HelpInfo
    Get-Help返回的帮助信息对象

.PARAMETER FilePath
    文件路径

.PARAMETER Type
    类型（Function或Script）
#>
function Convert-GetHelpToCustomObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$HelpInfo,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    # 提取参数信息
    $parameters = @()
    if ($HelpInfo.parameters -and $HelpInfo.parameters.parameter) {
        foreach ($param in $HelpInfo.parameters.parameter) {
            $parameters += [PSCustomObject]@{
                Name        = $param.name
                Description = if ($param.description) { $param.description.Text -join " " } else { "" }
            }
        }
    }
    
    # 提取示例信息
    $examples = @()
    if ($HelpInfo.examples -and $HelpInfo.examples.example) {
        foreach ($example in $HelpInfo.examples.example) {
            $exampleText = ""
            if ($example.code) {
                $exampleText += $example.code
            }
            if ($example.remarks) {
                $exampleText += "`n" + ($example.remarks.Text -join " ")
            }
            if (-not [string]::IsNullOrEmpty($exampleText)) {
                $examples += $exampleText.Trim()
            }
        }
    }
    
    return [PSCustomObject]@{
        Name        = $HelpInfo.Name
        Type        = $Type
        Synopsis    = if ($HelpInfo.Synopsis) { $HelpInfo.Synopsis } else { "无帮助信息" }
        Description = if ($HelpInfo.Description) { $HelpInfo.Description.Text -join " " } else { "无帮助信息" }
        Parameters  = $parameters
        Examples    = $examples
        FilePath    = $FilePath
        ModuleName  = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    }
}

<#
.SYNOPSIS
    解析PowerShell帮助注释块

.DESCRIPTION
    解析PowerShell函数或脚本的帮助注释块，提取Synopsis、Description、Parameters等信息

.PARAMETER HelpBlock
    帮助注释块的文本内容

.PARAMETER Name
    函数或脚本名称

.PARAMETER FilePath
    文件路径

.PARAMETER Type
    类型（Function或Script）

.OUTPUTS
    [PSCustomObject] 包含解析后帮助信息的对象
#>
function Parse-HelpBlock {
    <#
    .SYNOPSIS
        简要描述 Parse-HelpBlock 函数的功能
    
    .DESCRIPTION
        详细描述 Parse-HelpBlock 函数的用途、工作原理和使用场景
    
    .PARAMETER HelpBlock
        描述参数 HelpBlock 的用途和要求

    .PARAMETER Name
        描述参数 Name 的用途和要求

    .PARAMETER FilePath
        描述参数 FilePath 的用途和要求

    .PARAMETER Type
        描述参数 Type 的用途和要求

    .PARAMETER true
        描述参数 true 的用途和要求
    
    .EXAMPLE
        Parse-HelpBlock
        提供一个使用示例和说明
    
    .NOTES
        作者: [作者名]
        版本: 1.0.0
        创建日期: 2025-07-09
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$HelpBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    # 初始化结果对象
    $helpInfo = [PSCustomObject]@{
        Name        = $Name
        Type        = $Type
        Synopsis    = ""
        Description = ""
        Parameters  = @()
        Examples    = @()
        FilePath    = $FilePath
        ModuleName  = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    }
    
    # 提取Synopsis
    $synopsisMatch = [regex]::Match($HelpBlock, '\.SYNOPSIS\s*([\s\S]*?)(?=\.[A-Z]|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($synopsisMatch.Success) {
        $helpInfo.Synopsis = $synopsisMatch.Groups[1].Value.Trim()
    }
    
    # 提取Description
    $descriptionMatch = [regex]::Match($HelpBlock, '\.DESCRIPTION\s*([\s\S]*?)(?=\.[A-Z]|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($descriptionMatch.Success) {
        $helpInfo.Description = $descriptionMatch.Groups[1].Value.Trim()
    }
    
    # 提取Parameters
    $parameterMatches = [regex]::Matches($HelpBlock, '\.PARAMETER\s+(\w+)\s*([\s\S]*?)(?=\.[A-Z]|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $parameterMatches) {
        $paramInfo = [PSCustomObject]@{
            Name        = $match.Groups[1].Value.Trim()
            Description = $match.Groups[2].Value.Trim()
        }
        $helpInfo.Parameters += $paramInfo
    }
    
    # 提取Examples
    $exampleMatches = [regex]::Matches($HelpBlock, '\.EXAMPLE\s*([\s\S]*?)(?=\.[A-Z]|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $exampleMatches) {
        $helpInfo.Examples += $match.Groups[1].Value.Trim()
    }
    
    # 如果没有Synopsis，使用函数名作为默认值
    if ([string]::IsNullOrEmpty($helpInfo.Synopsis)) {
        $helpInfo.Synopsis = "无帮助信息"
    }
    
    # 如果没有Description，使用Synopsis
    if ([string]::IsNullOrEmpty($helpInfo.Description)) {
        $helpInfo.Description = $helpInfo.Synopsis
    }
    
    return $helpInfo
}

<#
.SYNOPSIS
    快速搜索当前psutils模块中的函数和脚本

.DESCRIPTION
    Search-ModuleHelp的简化版本，专门用于搜索当前psutils模块中的函数和脚本

.PARAMETER SearchTerm
    搜索关键词

.PARAMETER ShowDetails
    是否显示详细信息

.PARAMETER UseGetHelp
    是否使用Get-Help获取帮助信息

.PARAMETER IncludeScripts
    是否包含脚本文件搜索

.EXAMPLE
    Find-PSUtilsFunction "install"
    搜索包含"install"的函数

.EXAMPLE
    Find-PSUtilsFunction -ShowDetails -UseGetHelp
    使用Get-Help显示所有函数的详细信息

.EXAMPLE
    Find-PSUtilsFunction "config" -IncludeScripts
    搜索包含"config"的函数和脚本
#>
function Find-PSUtilsFunction {
    <#
    .SYNOPSIS
        简要描述 Find-PSUtilsFunction 函数的功能
    
    .DESCRIPTION
        详细描述 Find-PSUtilsFunction 函数的用途、工作原理和使用场景
    
    .PARAMETER SearchTerm
        描述参数 SearchTerm 的用途和要求

    .PARAMETER ShowDetails
        描述参数 ShowDetails 的用途和要求

    .PARAMETER UseGetHelp
        描述参数 UseGetHelp 的用途和要求

    .PARAMETER IncludeScripts
        描述参数 IncludeScripts 的用途和要求
    
    .EXAMPLE
        Find-PSUtilsFunction
        提供一个使用示例和说明
    
    .NOTES
        作者: [作者名]
        版本: 1.0.0
        创建日期: 2025-07-09
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$SearchTerm,
        
        [Parameter()]
        [switch]$ShowDetails,
        
        [Parameter()]
        [switch]$UseGetHelp,
        
        [Parameter()]
        [switch]$IncludeScripts
    )
    
    $modulePath = Split-Path -Parent $PSScriptRoot
    return Search-ModuleHelp -SearchTerm $SearchTerm -ModulePath $modulePath -ShowDetails:$ShowDetails -UseGetHelp:$UseGetHelp -IncludeScripts:$IncludeScripts
}

<#
.SYNOPSIS
    获取指定函数或脚本的详细帮助信息

.DESCRIPTION
    快速获取指定函数或脚本的完整帮助信息，包括参数说明和使用示例

.PARAMETER Name
    要查询的函数或脚本名

.PARAMETER ModulePath
    模块路径，默认为当前psutils模块

.PARAMETER UseGetHelp
    是否使用Get-Help获取帮助信息

.PARAMETER IncludeScripts
    是否包含脚本文件搜索

.EXAMPLE
    Get-FunctionHelp "Install-PackageManagerApps"
    获取Install-PackageManagerApps函数的详细帮助

.EXAMPLE
    Get-FunctionHelp "Get-OperatingSystem" -ModulePath "C:\MyModule" -UseGetHelp
    在指定模块中使用Get-Help查询函数帮助

.EXAMPLE
    Get-FunctionHelp "myScript" -IncludeScripts
    查询脚本文件的帮助信息
#>
function Get-FunctionHelp {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,
        
        [Parameter()]
        [string]$ModulePath = (Split-Path -Parent $PSScriptRoot),
        
        [Parameter()]
        [switch]$UseGetHelp,
        
        [Parameter()]
        [switch]$IncludeScripts
    )
    
    return Search-ModuleHelp -FunctionName $Name -ModulePath $ModulePath -ShowDetails -UseGetHelp:$UseGetHelp -IncludeScripts:$IncludeScripts
}

<#
.SYNOPSIS
    比较两种帮助搜索方法的性能

.DESCRIPTION
    对比自定义解析和Get-Help两种方法的性能差异

.PARAMETER SearchTerm
    搜索关键词

.PARAMETER ModulePath
    模块路径

.EXAMPLE
    Compare-HelpSearchPerformance "Get"
    比较搜索"Get"关键词的性能
#>
function Compare-HelpSearchPerformance {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$SearchTerm = "Get",
        
        [Parameter()]
        [string]$ModulePath = (Split-Path -Parent $PSScriptRoot)
    )
    
    Write-Host "性能对比测试 - 搜索关键词: '$SearchTerm'" -ForegroundColor Yellow
    Write-Host "模块路径: $ModulePath" -ForegroundColor Gray
    Write-Host ""
    
    # 测试自定义解析方法
    Write-Host "测试自定义解析方法..." -ForegroundColor Cyan
    $customTime = Measure-Command {
        $customResults = Search-ModuleHelp -SearchTerm $SearchTerm -ModulePath $ModulePath
    }
    
    Write-Host "自定义解析结果: 找到 $($customResults.Count) 个项目，耗时 $($customTime.TotalMilliseconds.ToString('F2')) 毫秒" -ForegroundColor Green
    
    # 测试Get-Help方法
    Write-Host "测试Get-Help方法..." -ForegroundColor Cyan
    $getHelpTime = Measure-Command {
        $getHelpResults = Search-ModuleHelp -SearchTerm $SearchTerm -ModulePath $ModulePath -UseGetHelp
    }
    
    Write-Host "Get-Help结果: 找到 $($getHelpResults.Count) 个项目，耗时 $($getHelpTime.TotalMilliseconds.ToString('F2')) 毫秒" -ForegroundColor Green
    
    # 性能对比
    Write-Host ""
    Write-Host "性能对比:" -ForegroundColor Yellow
    $speedup = $getHelpTime.TotalMilliseconds / $customTime.TotalMilliseconds
    if ($speedup -gt 1) {
        Write-Host "自定义解析比Get-Help快 $($speedup.ToString('F2')) 倍" -ForegroundColor Green
    }
    else {
        Write-Host "Get-Help比自定义解析快 $((1/$speedup).ToString('F2')) 倍" -ForegroundColor Red
    }
}

# 导出函数
Export-ModuleMember -Function Search-ModuleHelp, Find-PSUtilsFunction, Get-FunctionHelp, Compare-HelpSearchPerformance, Parse-HelpBlock









