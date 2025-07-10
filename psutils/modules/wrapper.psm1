# 这个文件放置对powershell内置命令包装增强的方法

$Global:DefaultAliasDespPrefix = '[用户自定义] '
function Set-CustomAlias {
    <#
    .SYNOPSIS
        为 Set-Alias 提供的一个包装函数，可以自动为别名添加描述前缀，方便用户识别和筛选。

    .DESCRIPTION
        此函数完全兼容原生的 Set-Alias cmdlet，并接受其所有参数（如 -Name, -Value, -Force, -Option 等）。
        它额外增加了一个 -AliasDespPrefix 参数，其值会自动添加到别名描述（Description）的开头。
        这样做的好处是，之后你可以通过 Get-Alias 并筛选描述前缀，轻松地找出所有由你自定义的别名。

    .PARAMETER Name
        指定要创建的别名的名称。此参数与 Set-Alias 中的 -Name 完全相同。

    .PARAMETER Value
        指定别名所代表的 cmdlet、函数、脚本或命令。此参数与 Set-Alias 中的 -Value 完全相同。

    .PARAMETER Description
        为别名提供一个可选的描述。你提供的描述会自动跟在 -AliasDespPrefix 参数定义的文本之后。
        此参数与 Set-Alias 中的 -Description 完全相同。

    .PARAMETER AliasDespPrefix
        一个自定义的字符串前缀，将被添加到所有通过此函数创建的别名的描述信息中。
        这可以作为一个标记，方便以后筛选。默认值为 "[用户自定义] "。

    .PARAMETER Force
        强制创建别名，即使已存在同名别名也会覆盖。此参数与 Set-Alias 中的 -Force 完全相同。

    .PARAMETER Option
        设置别名的选项，如 ReadOnly 或 AllScope。此参数与 Set-Alias 中的 -Option 完全相同。

    .EXAMPLE
        PS C:\> Set-CustomAlias -Name lg -Value "lazygit.exe" -Description "启动 lazygit 终端UI"

        描述:
        创建一个名为 "lg" 的别名。最终别名的描述将是 "[用户自定义] 启动 lazygit 终端UI"。

    .EXAMPLE
        PS C:\> Set-CustomAlias -Name psedit -Value "code $PROFILE"

        描述:
        创建一个名为 "psedit" 的别名，用于快速编辑 PowerShell 配置文件。
        由于未提供 -Description，最终描述将仅为 "[用户自定义] "。

    .EXAMPLE
        PS C:\> Set-CustomAlias -Name vi -Value "nvim.exe" -AliasDespPrefix "[编辑器] " -Description "使用 Neovim"

        描述:
        创建一个名为 "vi" 的别名，并自定义了描述前缀。
        最终别名的描述将是 "[编辑器] 使用 Neovim"。

    .EXAMPLE
        PS C:\> # 如何筛选出所有自定义的别名
        PS C:\> Get-Alias | Where-Object { $_.Description -like "*[用户自定义]*" }

        描述:
        演示如何使用 Where-Object 和 -like 通配符来找出所有通过此函数（使用默认前缀）创建的别名。

    .NOTES
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string]$AliasDespPrefix = $Global:DefaultAliasDespPrefix, # 定义我们新的参数，并给予默认值

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ScopedItemOptions]$Option,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru,

        [Parameter(Mandatory = $false)]
        [string]$Scope
    )

    # Begin, Process, End 块确保函数行为更像一个标准的 cmdlet
    process {
        Write-Verbose "[Set-CustomAlias] 开始处理别名 '$Name' -> '$Value'"

        # 1. 准备要传递给 Set-Alias 的参数哈希表
        # 创建一个 $PSBoundParameters 的副本，这样我们可以安全地修改它
        Write-Verbose "[Set-CustomAlias] 准备传递给 Set-Alias 的参数哈希表..."
        $parametersForSetAlias = @{} + $PSBoundParameters

        # 2. 准备新的描述字符串
        # 这里的逻辑不变，因为 $AliasDespPrefix 总是有值的（要么用户提供，要么是默认值）
        Write-Verbose "[Set-CustomAlias] 准备别名描述..."
        $newDescription = $AliasDespPrefix
        if ($parametersForSetAlias.ContainsKey('Description')) {
            $newDescription += $parametersForSetAlias['Description']
            Write-Verbose "[Set-CustomAlias] 原始描述存在，合并描述。"
        }
        $parametersForSetAlias['Description'] = $newDescription
        Write-Verbose "[Set-CustomAlias] 最终描述: '$newDescription'"

        # 3. 【修正】从哈希表中移除我们自定义的参数
        # 只有当用户确实绑定了这个参数时，才去移除它
        if ($parametersForSetAlias.ContainsKey('AliasDespPrefix')) {
            Write-Verbose "[Set-CustomAlias] 从参数列表中移除 AliasDespPrefix 参数。"
            $parametersForSetAlias.Remove('AliasDespPrefix') | Out-Null
        }
        
        try {
            Write-Verbose "[Set-CustomAlias] 调用原生 Set-Alias..."
            # 使用 "Splatting" 技术将准备好的参数传递给原生的 Set-Alias cmdlet
            Set-Alias @parametersForSetAlias
            Write-Verbose "[Set-CustomAlias] 别名 '$Name' 设置成功。"
        }
        catch {
            # 如果出现错误，则抛出，保持和原生 cmdlet 一致的行为
            Write-Error "创建别名失败: $_"
            Write-Verbose "[Set-CustomAlias] 创建别名 '$Name' 失败。错误: $($_.Exception.Message)"
        }
    }
}

function Get-CustomAlias {
    <#
    .SYNOPSIS
        为 Get-Alias 提供的一个包装函数，可以方便地筛选出由 Set-CustomAlias 创建的别名。

    .DESCRIPTION
        此函数包装了原生的 Get-Alias cmdlet。它的主要增强功能是通过 -AliasDespPrefix 参数，
        可以快速地筛选出那些描述信息中包含特定前缀的别名。
        这与我们之前创建的 Set-CustomAlias 函数完美配合，形成了一套完整的自定义别名管理方案。
        当不提供任何参数时，它的行为与原生的 Get-Alias 完全相同。

    .PARAMETER Name
        指定要获取的一个或多个别名的名称。支持通配符。
        此参数与 Get-Alias 中的 -Name 完全相同。

    .PARAMETER AliasDespPrefix
        一个用于筛选的字符串前缀。函数将只返回那些描述（Description）以这个前缀开头的别名。
        你可以提供一个数组来进行多种前缀的 "或" 筛选。
        如果想查找所有自定义别名，可以传入 "*[用户自定义]*" 或 "*[编辑器]*" 等模式。

    .PARAMETER Exclude
        指定要从此函数返回结果中排除的别名。支持通配符。

    .PARAMETER Scope
        指定此别名所在的范围。

    .EXAMPLE
        PS C:\> Get-CustomAlias

        描述:
        当不带任何参数时，此函数的行为与 'Get-Alias' 完全相同，返回所有别名。

    .EXAMPLE
        PS C:\> Get-CustomAlias -AliasDespPrefix "[用户自定义] "

        描述:
        查找并列出所有描述以 "[用户自定义] " 开头的别名。这是查找你大部分自定义别名的最快方式。

    .EXAMPLE
        PS C:\> Get-CustomAlias -AliasDespPrefix "[用户自定义] ", "[编辑器] "

        描述:
        查找所有描述以 "[用户自定义] " 或 "[编辑器] " 开头的别名。

    .EXAMPLE
        PS C:\> Get-CustomAlias -Name "l*" -AliasDespPrefix "[用户自定义] "

        描述:
        查找所有以 "l" 开头，并且描述中带有 "[用户自定义] " 前缀的别名。

    .NOTES
        作者: mudssky
        版本: 1.0
        此函数利用了 PowerShell 管道的强大能力。它首先调用原生的 Get-Alias 获取一个初始列表，
        然后根据需要通过 Where-Object 进行二次筛选。
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(Mandatory = $false)]
        [string]$AliasDespPrefix = $Global:DefaultAliasDespPrefix, 

        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Exclude,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$Scope
    )

    # Begin 块用于准备参数
    begin {
        Write-Verbose "[Get-CustomAlias] 开始获取别名。"
        # 准备要传递给原生 Get-Alias 的参数哈希表
        Write-Verbose "[Get-CustomAlias] 准备传递给 Get-Alias 的参数哈希表..."
        $paramsForGetAlias = @{} + $PSBoundParameters
        
        # 从哈希表中移除我们自己的参数，因为 Get-Alias 不认识它
        if ($paramsForGetAlias.ContainsKey('AliasDespPrefix')) {
            Write-Verbose "[Get-CustomAlias] 从参数列表中移除 AliasDespPrefix 参数。"
            $paramsForGetAlias.Remove('AliasDespPrefix') | Out-Null
        }
    }

    # Process 块是核心逻辑
    process {
        try {
            Write-Verbose "[Get-CustomAlias] 调用原生 Get-Alias..."
            # 1. 首先，调用原生的 Get-Alias，并将结果存储在一个变量中
            # 使用 Splatting 技术传递所有兼容的参数
            $aliases = Get-Alias @paramsForGetAlias
            Write-Verbose "[Get-CustomAlias] 成功获取原生别名列表。"

            # 2. 检查用户是否提供了 -AliasDespPrefix 参数
            if ($PSBoundParameters.ContainsKey('AliasDespPrefix')) {
                Write-Verbose "[Get-CustomAlias] 检测到 AliasDespPrefix 参数，执行筛选。"
                # 将用户提供的前缀赋值给一个局部变量，以供筛选使用
                $PrefixesToFilter = $PSBoundParameters['AliasDespPrefix']
                $aliases = $aliases | Where-Object {
                    $aliasToTest = $_
                    Write-Verbose "[Get-CustomAlias] 检查别名 '$($aliasToTest.Name)' 描述: '$($aliasToTest.Description)' 是否匹配前缀 '$PrefixesToFilter'。"
                    if ($aliasToTest.Description -like "*$PrefixesToFilter*") {
                        return $true
                    }
                    
                    return $false
                }
                Write-Verbose "[Get-CustomAlias] 筛选完成。"
            }
            else {
                Write-Verbose "[Get-CustomAlias] 未提供 AliasDespPrefix 参数，使用默认值 '$Global:DefaultAliasDespPrefix' 进行筛选。"
                # 用户没提供，用默认值筛选
                $aliases = $aliases | Where-Object {
                    $aliasToTest = $_
                    # Write-Host "------------------------------"
                    if ($aliasToTest.Description -like "$AliasDespPrefix*") {
                        # 使用 return $true 是 Where-Object 脚本块的一个有效技巧
                        return $true
                    }
                    
                    return $false
                }
                Write-Verbose "[Get-CustomAlias] 默认筛选完成。"
            }

            # 输出最终结果
            Write-Output $aliases
            Write-Verbose "[Get-CustomAlias] 别名获取和筛选流程完成。"

        }
        catch {
            Write-Error "获取别名失败: $_"
            Write-Verbose "[Get-CustomAlias] 获取别名失败。错误: $($_.Exception.Message)"
        }
    }
}


Export-ModuleMember -Function *