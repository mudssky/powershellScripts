Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    从 AST 中提取静态命令名引用。

.DESCRIPTION
    仅收集 PowerShell AST 可以静态识别的命令名，
    供 bundle 依赖闭包分析判断哪些共享函数被入口源码直接或间接引用。

.PARAMETER Ast
    要分析的 PowerShell AST 节点。

.OUTPUTS
    string[]
    返回去重后的命令名数组。
#>
function Get-BundleAstCommandNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    return @(
        $Ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            },
            $true
        ) |
            ForEach-Object { $_.GetCommandName() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

<#
.SYNOPSIS
    判断命令名是否已由运行时或入口源码提供。

.DESCRIPTION
    在共享闭包分析中，用来区分“需要从共享源码补入的函数”和
    “已经由入口源码或 PowerShell 运行时解析得到的命令”。

.PARAMETER CommandName
    要检测的命令名。

.PARAMETER LocalFunctionNames
    入口源码已定义的函数名集合。

.OUTPUTS
    bool
    返回命令是否可直接解析，无需从共享源码补入。
#>
function Test-BundleCommandResolvable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$LocalFunctionNames
    )

    if ($LocalFunctionNames.Contains($CommandName)) {
        return $true
    }

    $resolvedCommands = @(
        Get-Command -Name $CommandName -All -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandType -ne [System.Management.Automation.CommandTypes]::Function }
    )

    return $resolvedCommands.Count -gt 0
}

<#
.SYNOPSIS
    收集入口源码自身定义的函数名。

.DESCRIPTION
    先建立入口源码本地函数索引，避免把 toolkit 内部已经存在的函数误判成缺失共享依赖。

.PARAMETER EntryPaths
    入口源码文件路径列表。

.OUTPUTS
    HashSet[string]
    返回入口源码定义的函数名集合。
#>
function Get-BundleEntryFunctionNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$EntryPaths
    )

    $functionNames = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($entryPath in $EntryPaths) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            $errorText = ($errors | ForEach-Object { $_.Message }) -join '; '
            throw "解析入口源码失败: ${entryPath}: $errorText"
        }

        foreach ($functionAst in $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                },
                $true
            )) {
            $functionNames.Add($functionAst.Name) | Out-Null
        }
    }

    return $functionNames
}

<#
.SYNOPSIS
    为共享源码建立函数索引。

.DESCRIPTION
    递归扫描共享源码根目录下的 `.ps1` 文件，
    建立函数定义、源码文本和静态引用的索引，供 bundle 闭包分析复用。

.PARAMETER RootPaths
    共享源码根目录列表。

.OUTPUTS
    hashtable
    返回函数名到定义描述对象的映射。
#>
function Get-BundleFunctionIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RootPaths
    )

    $index = @{}
    foreach ($rootPath in $RootPaths) {
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
            continue
        }

        foreach ($file in Get-ChildItem -LiteralPath $rootPath -Filter '*.ps1' -Recurse | Sort-Object FullName) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                $errorText = ($errors | ForEach-Object { $_.Message }) -join '; '
                throw "解析共享源码失败: $($file.FullName): $errorText"
            }

            foreach ($functionAst in $ast.FindAll(
                    {
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    },
                    $true
                )) {
                if ($index.ContainsKey($functionAst.Name)) {
                    throw '重复函数定义'
                }

                $index[$functionAst.Name] = [pscustomobject]@{
                    Name       = $functionAst.Name
                    Path       = $file.FullName
                    Content    = $functionAst.Extent.Text
                    References = Get-BundleAstCommandNames -Ast $functionAst.Body
                }
            }
        }
    }

    return $index
}

<#
.SYNOPSIS
    收集入口源码对共享函数的直接引用。

.DESCRIPTION
    当入口源码引用了共享函数索引中的函数名时纳入闭包起点；
    若既不属于入口源码本地函数，也无法由运行时解析，则视为缺失共享定义并抛错。

.PARAMETER EntryPaths
    入口源码文件路径列表。

.PARAMETER FunctionIndex
    共享函数索引。

.OUTPUTS
    string[]
    返回去重后的共享函数入口引用列表。
#>
function Get-BundleEntrySharedReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$EntryPaths,

        [Parameter(Mandatory)]
        [hashtable]$FunctionIndex
    )

    $references = New-Object 'System.Collections.Generic.HashSet[string]'
    $entryFunctionNames = Get-BundleEntryFunctionNames -EntryPaths $EntryPaths

    foreach ($entryPath in $EntryPaths) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            $errorText = ($errors | ForEach-Object { $_.Message }) -join '; '
            throw "解析入口源码失败: ${entryPath}: $errorText"
        }

        foreach ($commandName in Get-BundleAstCommandNames -Ast $ast) {
            if ($FunctionIndex.ContainsKey($commandName)) {
                $references.Add($commandName) | Out-Null
                continue
            }

            if (-not (Test-BundleCommandResolvable -CommandName $commandName -LocalFunctionNames $entryFunctionNames)) {
                throw '未找到共享函数定义'
            }
        }
    }

    return @($references | ForEach-Object { $_ })
}

<#
.SYNOPSIS
    深度优先解析单个共享函数的依赖闭包。

.DESCRIPTION
    通过 DFS 保证共享函数按“依赖在前、使用者在后”的顺序输出，
    同时检测循环依赖和缺失定义。

.PARAMETER FunctionName
    当前要解析的共享函数名。

.PARAMETER FunctionIndex
    共享函数索引。

.PARAMETER Visited
    已完成解析的函数集合。

.PARAMETER Active
    当前 DFS 调用栈中的函数集合，用于检测循环依赖。

.PARAMETER OrderedFunctions
    依赖优先顺序的输出列表。

.PARAMETER LocalFunctionNames
    入口源码已定义的函数名集合。
#>
function Resolve-BundleFunctionClosureNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,

        [Parameter(Mandatory)]
        [hashtable]$FunctionIndex,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Visited,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Active,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$OrderedFunctions,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$LocalFunctionNames
    )

    if ($Visited.Contains($FunctionName)) {
        return
    }

    if (-not $FunctionIndex.ContainsKey($FunctionName)) {
        throw '未找到共享函数定义'
    }

    if ($Active.Contains($FunctionName)) {
        throw "检测到共享函数循环依赖: $FunctionName"
    }

    $Active.Add($FunctionName) | Out-Null
    $functionDefinition = $FunctionIndex[$FunctionName]
    foreach ($reference in $functionDefinition.References) {
        if ($FunctionIndex.ContainsKey($reference)) {
            Resolve-BundleFunctionClosureNode -FunctionName $reference -FunctionIndex $FunctionIndex -Visited $Visited -Active $Active -OrderedFunctions $OrderedFunctions -LocalFunctionNames $LocalFunctionNames
            continue
        }

        if (-not (Test-BundleCommandResolvable -CommandName $reference -LocalFunctionNames $LocalFunctionNames)) {
            throw '未找到共享函数定义'
        }
    }

    $Active.Remove($FunctionName) | Out-Null
    $Visited.Add($FunctionName) | Out-Null
    $OrderedFunctions.Add($functionDefinition) | Out-Null
}

<#
.SYNOPSIS
    计算入口源码需要打包的共享函数闭包。

.DESCRIPTION
    从入口源码直接引用的共享函数开始，递归收集所有共享依赖，
    返回按依赖优先顺序排列的函数定义集合。

.PARAMETER EntryPaths
    入口源码文件路径列表。

.PARAMETER FunctionIndex
    共享函数索引。

.OUTPUTS
    PSCustomObject
    返回 `Functions`、`FunctionNames` 与 `Contents` 三个成员。
#>
function Get-BundleFunctionClosure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$EntryPaths,

        [Parameter(Mandatory)]
        [hashtable]$FunctionIndex
    )

    $orderedFunctions = New-Object 'System.Collections.Generic.List[object]'
    $visited = New-Object 'System.Collections.Generic.HashSet[string]'
    $active = New-Object 'System.Collections.Generic.HashSet[string]'
    $entryFunctionNames = Get-BundleEntryFunctionNames -EntryPaths $EntryPaths

    foreach ($functionName in Get-BundleEntrySharedReferences -EntryPaths $EntryPaths -FunctionIndex $FunctionIndex) {
        Resolve-BundleFunctionClosureNode -FunctionName $functionName -FunctionIndex $FunctionIndex -Visited $visited -Active $active -OrderedFunctions $orderedFunctions -LocalFunctionNames $entryFunctionNames
    }

    $orderedFunctionArray = @($orderedFunctions | ForEach-Object { $_ })

    return [pscustomobject]@{
        Functions     = $orderedFunctionArray
        FunctionNames = @($orderedFunctionArray | ForEach-Object { $_.Name })
        Contents      = @($orderedFunctionArray | ForEach-Object { $_.Content })
    }
}
