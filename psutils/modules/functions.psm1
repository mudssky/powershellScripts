

<#
.SYNOPSIS
    获取PowerShell历史命令的使用频率排名
.DESCRIPTION
    此函数分析PowerShell历史命令文件，统计每个命令的执行次数，并按频率降序排列，显示前N个最常用的命令及其使用百分比。
.PARAMETER top
    要显示的历史命令数量，默认为10。
.OUTPUTS
    System.Management.Automation.PSObject
    包含命令名称、执行次数和使用百分比的格式化表格。
.EXAMPLE
    Get-HistoryCommandRank
    显示前10个最常用的历史命令。
.EXAMPLE
    Get-HistoryCommandRank -top 5
    显示前5个最常用的历史命令。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 帮助用户了解其PowerShell命令使用习惯。
    历史命令文件路径: $env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt
#>
function Get-HistoryCommandRank([int]$top = 10) {
    $count = 0; Get-Content  $env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | 
        ForEach-Object { ($_ -split ' ')[0]; $count += 1 } | 
        Group-Object | Sort-Object -Property Count  -Descending  -Top $top |
        Format-Table -Property Name, Count, @{Label = "Percentage"; Expression = { '{0:p2}' -f ($_.Count / $count) } } -AutoSize
}

# 获取脚本执行目录
<#
.SYNOPSIS
    获取当前脚本所在的文件夹路径
.DESCRIPTION
    此函数返回当前正在执行的PowerShell脚本所在的完整目录路径。
    这对于需要引用与脚本相对路径的资源或文件非常有用。
.OUTPUTS
    System.String
    当前脚本的完整文件夹路径。
.EXAMPLE
    $scriptDir = Get-ScriptFolder
    Write-Host "当前脚本目录: $scriptDir"
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便脚本内部进行路径管理和资源引用。
#>
function Get-ScriptFolder() {
    $currentScriptPath = $MyInvocation.MyCommand.Definition
    $currentScriptFolder = Split-Path  -Parent   $currentScriptPath 
    return $currentScriptFolder
}




<#
.SYNOPSIS
    启动IPython交互式Python环境
.DESCRIPTION
    此函数在PowerShell中启动IPython交互式Python环境。前提是系统中已安装Python和IPython。
.OUTPUTS
    无。直接启动IPython进程。
.EXAMPLE
    Start-Ipython
    启动IPython。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便快速进入IPython环境进行Python开发和调试。
    需要预先安装Python和IPython (`pip install ipython`).
#>
function Start-Ipython () {
    python -m IPython
}

<#
.SYNOPSIS
    安装并配置PSReadLine模块
.DESCRIPTION
    此函数用于安装PowerShell的PSReadLine模块，并配置其历史记录预测源。
    PSReadLine提供了增强的命令行编辑体验，包括语法高亮、命令历史记录、Tab补全等。
.OUTPUTS
    无。安装并配置PSReadLine模块。
.EXAMPLE
    Start-PSReadline
    安装PSReadLine模块并启用历史记录预测。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 提升PowerShell命令行交互体验。
    如果模块已安装，则会强制重新安装。
#>
function Start-PSReadline() {
    # 安装
    Install-Module -Name PSReadLine -AllowClobber -Force
    # 开启基于历史记录的智能提示
    Set-PSReadLineOption -PredictionSource History
}

<#
.SYNOPSIS
    使用 fzf 智能检索 PowerShell 历史命令
.DESCRIPTION
    打开 fzf 历史命令选择器，并支持三种动作：
    - Enter: 仅填充到当前命令行，不立即执行
    - Ctrl+E: 立即执行选中命令
    - Ctrl+Y: 复制选中命令到剪贴板
    默认会对历史去重，并优先保留最近一次出现的命令。
.OUTPUTS
    无
#>
function Invoke-FzfHistorySmart {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name fzf -ErrorAction SilentlyContinue)) {
        Write-Warning '未检测到 fzf，跳过历史检索。'
        return
    }

    $historyFile = $null
    try {
        $historyFile = (Get-PSReadLineOption).HistorySavePath
    }
    catch {
        Write-Verbose "无法获取 PSReadLine 历史文件路径: $($_.Exception.Message)"
        return
    }

    if ([string]::IsNullOrWhiteSpace($historyFile) -or -not (Test-Path -LiteralPath $historyFile)) {
        return
    }

    $historyRaw = @(Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue)
    if ($historyRaw.Count -eq 0) {
        return
    }

    # 从最近命令向前去重，保留每条命令的最新一条
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $historyUnique = [System.Collections.Generic.List[string]]::new()
    for ($i = $historyRaw.Count - 1; $i -ge 0; $i--) {
        $line = [string]$historyRaw[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($seen.Add($line)) {
            $historyUnique.Add($line) | Out-Null
        }
    }

    if ($historyUnique.Count -eq 0) {
        return
    }

    $fzfArgs = @(
        '--no-sort',
        '--height=40%',
        '--reverse',
        '--header=[Enter]:放入命令行 | [Ctrl-E]:立即执行 | [Ctrl-Y]:复制到剪贴板',
        '--expect=ctrl-e,ctrl-y'
    )

    $result = $historyUnique | fzf @fzfArgs

    if (-not $result) {
        return
    }

    $resultLines = @($result)
    $key = ''
    $selection = $null

    if ($resultLines.Count -eq 1) {
        $selection = [string]$resultLines[0]
    }
    elseif ($resultLines.Count -ge 2) {
        $key = [string]$resultLines[0]
        $selection = [string]$resultLines[1]
    }

    $key = $key.Trim()
    if ($null -ne $selection) {
        $selection = $selection.TrimEnd("`r", "`n")
    }

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return
    }

    switch ($key) {
        'ctrl-e' {
            Write-Host "`n[Running]: $selection" -ForegroundColor Cyan
            try {
                Invoke-Expression $selection
            }
            catch {
                Write-Error "执行历史命令失败: $($_.Exception.Message)"
            }
        }
        'ctrl-y' {
            if (Get-Command -Name Set-Clipboard -ErrorAction SilentlyContinue) {
                $selection | Set-Clipboard
                Write-Host "`n[Copied to clipboard]" -ForegroundColor Green
            }
            else {
                Write-Warning '当前环境不支持 Set-Clipboard，无法复制到剪贴板。'
            }
        }
        default {
            $inserted = $false
            if ([System.Management.Automation.PSTypeName]'Microsoft.PowerShell.PSConsoleReadLine'.Type) {
                try {
                    $line = ''
                    $cursor = 0
                    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $selection)
                    [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
                    $inserted = $true
                }
                catch {
                    Write-Verbose "PSReadLine 回填失败，降级为输出文本: $($_.Exception.Message)"
                }
            }

            if (-not $inserted) {
                Write-Output $selection
            }
        }
    }
}

<#
.SYNOPSIS
    绑定 fzf 智能历史搜索快捷键
.DESCRIPTION
    为 PSReadLine 注册快捷键，默认 `Alt+h`，触发 `Invoke-FzfHistorySmart`。
.PARAMETER Key
    要绑定的快捷键，默认 `Alt+h`。
.OUTPUTS
    System.Boolean
    绑定成功返回 `$true`，否则返回 `$false`。
#>
function Register-FzfHistorySmartKeyBinding {
    [CmdletBinding()]
    param(
        [string]$Key = 'Alt+h'
    )

    if (-not (Get-Command -Name Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
        Write-Verbose '未检测到 PSReadLine，跳过 fzf 历史快捷键绑定。'
        return $false
    }

    if (-not (Get-Command -Name fzf -ErrorAction SilentlyContinue)) {
        Write-Verbose '未检测到 fzf，跳过历史快捷键绑定。'
        return $false
    }

    Set-PSReadLineKeyHandler -Key $Key -BriefDescription 'fzf-history-smart' -Description '使用 fzf 搜索历史命令' -ScriptBlock {
        Invoke-FzfHistorySmart
    }

    return $true
}






<#
.SYNOPSIS
    创建Windows快捷方式
.DESCRIPTION
    此函数用于在Windows系统中创建快捷方式（.lnk文件）。
    它允许指定快捷方式的目标路径和快捷方式文件的保存路径。
.PARAMETER Path
    快捷方式的目标路径，即快捷方式指向的文件或文件夹的路径。
.PARAMETER Destination
    快捷方式文件（.lnk）的完整保存路径，包括文件名和扩展名。
.OUTPUTS
    无。在指定位置创建快捷方式文件。
.EXAMPLE
    New-Shortcut -Path "C:\Program Files\MyApp\MyApp.exe" -Destination "C:\Users\Public\Desktop\MyApp.lnk"
    为MyApp.exe创建一个桌面快捷方式。
.EXAMPLE
    New-Shortcut -Path "C:\MyDocuments" -Destination "C:\Users\Public\Desktop\MyDocs.lnk"
    为MyDocuments文件夹创建一个桌面快捷方式。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便自动化创建桌面、开始菜单或任何位置的快捷方式。
    此函数仅适用于Windows操作系统。
#>
function New-Shortcut {
    [CmdletBinding()]
    param (
        # 需要创建快捷方式的目标路径
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination 
    )
	
    begin {
	
    }
	
    process {
        $shell = New-Object -ComObject "WScript.Shell"
        $link = $shell.CreateShortcut($Destination)
        $link.TargetPath = $Path
        $link.Save()
    }
	
    end {
		
    }
}


# 设置package.json的scripts字段
<#
.SYNOPSIS
    设置或更新package.json文件中的scripts字段
.DESCRIPTION
    此函数用于向package.json文件的"scripts"字段添加新的脚本命令，或者更新现有脚本命令。
    它会读取package.json文件，修改scripts字段，然后将更新后的内容写回文件。
.PARAMETER key
    要设置或更新的脚本命令的名称（例如 "start", "build"）。
.PARAMETER value
    与脚本命令名称关联的实际命令字符串（例如 "node index.js", "webpack --config webpack.config.js"）。
.PARAMETER path
    package.json文件的完整路径。
.OUTPUTS
    无。直接修改指定路径的package.json文件。
.EXAMPLE
    Set-Script -key "dev" -value "nodemon app.js" -path ".\package.json"
    在当前目录的package.json中添加或更新一个名为"dev"的脚本。
.EXAMPLE
    Set-Script -key "test" -value "jest" -path "C:\Projects\MyProject\package.json"
    更新指定路径下package.json中的"test"脚本。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 自动化管理Node.js项目的package.json脚本。
    此函数会覆盖同名的现有脚本。
#>
function Set-Script {
    [CmdletBinding()]
    param (
        [string]$key , # 脚本名
        [string]$value,
        [string]$path # package.json路径
    )
	
    $jsonMap = Get-Content $path | ConvertFrom-Json -AsHashtable
    if ($jsonMap.scripts.ContainsKey($key)) {
        $jsonMap.scripts.$key = $value
    }
    else {
        $jsonMap.scripts.Add($key, $value)
    }
    ConvertTo-Json $jsonMap -Depth 100 | Out-File $path

}

# 更新semver字符串
<#
.SYNOPSIS
    更新语义化版本号（SemVer）字符串
.DESCRIPTION
    此函数根据指定的更新类型（major, minor, 或 patch）递增语义化版本号。
    它解析输入的版本字符串，递增相应的版本部分，并返回新的版本字符串。
.PARAMETER Version
    要更新的语义化版本字符串，格式必须为 "X.Y.Z"（例如 "1.0.0"）。
.PARAMETER UpdateType
    指定要递增的版本部分：
    - 'major': 递增主版本号，并将次版本号和修订版本号重置为0。
    - 'minor': 递增次版本号，并将修订版本号重置为0。
    - 'patch': 递增修订版本号。
    默认为 'patch'。
.OUTPUTS
    System.String
    更新后的语义化版本字符串。
.EXAMPLE
    Update-Semver -Version "1.2.3" -UpdateType "patch"
    返回 "1.2.4"
.EXAMPLE
    Update-Semver -Version "1.2.3" -UpdateType "minor"
    返回 "1.3.0"
.EXAMPLE
    Update-Semver -Version "1.2.3" -UpdateType "major"
    返回 "2.0.0"
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 自动化版本控制和发布流程。
    输入的版本字符串必须严格遵循 "X.Y.Z" 的格式，否则将报错。
#>
function Update-Semver {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version,	# 版本字符串
        [ValidateSet('major', 'minor', 'patch')]
        [string]$UpdateType = 'patch'     
    )
    $regexPattern = "^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$"
    $regexResult = $Version -match $regexPattern
    if (-not $regexResult) {
        Write-Error "无法解析SemVer版本字符串"
        return 
    }
    # 从正则表达式匹配结果中获取版本号各部分
    $majorVersion = [int]$matches["major"]
    $minorVersion = [int]$matches["minor"]
    $patchVersion = [int]$matches["patch"]
    switch ($UpdateType) {
        'major' {
            $majorVersion++
        }
        'minor' {
            $minorVersion++
        }
        'patch' {
            $patchVersion++
        }
    }
    $newVersion = "$($majorVersion).$($minorVersion).$($patchVersion)"
    return $newVersion
}



<#
.SYNOPSIS
    获取格式化的文件大小字符串
.DESCRIPTION
    此函数将字节数转换为更易读的格式（B, KB, MB, GB），并保留两位小数。
    当数值超过1024时，会自动采用更大的单位。
.PARAMETER length
    要格式化的文件大小，以字节（B）为单位。
.OUTPUTS
    System.String
    格式化后的文件大小字符串（例如 "10.24 KB", "1.50 MB", "2.33 GB"）。
.EXAMPLE
    Get-FormatLength -length 1024
    返回 "1.00 KB"
.EXAMPLE
    Get-FormatLength -length 1536000
    返回 "1.46 MB"
.EXAMPLE
    Get-FormatLength -length 2500000000
    返回 "2.33 GB"
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便在脚本中显示文件大小，提高可读性。
#>
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



<#
.SYNOPSIS
    获取表示一个十进制数所需的最小二进制位数
.DESCRIPTION
    此函数计算一个给定的十进制整数在二进制表示下所需的最小位数。
    它通过循环左移操作来确定数字的范围，从而得出所需的二进制位数。
.PARAMETER number
    要计算的十进制整数。
.OUTPUTS
    System.Int32
    表示该数字所需的最小二进制位数。如果输入数字超出Int64范围，则会输出错误信息。
.EXAMPLE
    Get-NeedBinaryDigit -number 1
    返回 1
.EXAMPLE
    Get-NeedBinaryDigit -number 2
    返回 2
.EXAMPLE
    Get-NeedBinaryDigit -number 1023
    返回 10
.EXAMPLE
    Get-NeedBinaryDigit -number 1024
    返回 11
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 在需要进行位操作或存储优化时，确定数据所需的最小存储空间。
    由于PowerShell中最大的数字类型是Int64，此函数处理的最大数字为2^63 - 1。
#>
function Get-NeedBinaryDigit($number) {
    # 由于powershell中最大的数字就是int64,2左移62位的时候就溢出了，所以最大比较到2左移61位。也就是2的62次方，2的63次方就会溢出int64
    # int64 有64位，其中一位是符号位， 所以表达的最大数就是 2的63次方-1（最高位下标是63）
    if ($number -gt ([int64]::MaxValue)) {
        Write-Host -ForegroundColor Red "the number is exceed the area of int64"
    }
    else {
        for ($i = 62; $i -gt 0; $i -= 1) {
            if ( ([int64](1) -shl $i) -lt $number) {
                return ($i + 1)
            }
        }
    }
}

<#
.SYNOPSIS
    从现有哈希表（字典）创建反转的哈希表
.DESCRIPTION
    此函数接受一个哈希表作为输入，并返回一个新的哈希表，
    其中原始哈希表的键成为新哈希表的值，原始哈希表的值成为新哈希表的键。
    如果原始哈希表的值不是唯一的，则反转后的哈希表将只保留最后一个遇到的键值对。
.PARAMETER map
    要反转的哈希表（字典）。
.OUTPUTS
    System.Collections.Hashtable
    反转后的哈希表。
.EXAMPLE
    $myMap = @{"Key1"="ValueA"; "Key2"="ValueB"}
    Get-ReversedMap -map $myMap
    返回 @{"ValueA"="Key1"; "ValueB"="Key2"}
.EXAMPLE
    $colorMap = @{"Red"="#FF0000"; "Green"="#00FF00"; "Blue"="#0000FF"}
    Get-ReversedMap -map $colorMap
    返回 @{"#FF0000"="Red"; "#00FF00"="Green"; "#0000FF"="Blue"}
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 在需要快速查找值对应的键时非常有用，例如在数据转换或查找表中。
    请注意，如果原始哈希表的值不唯一，反转后可能会丢失数据。
#>
function Get-ReversedMap($map) {
    $reversedMap = @{}
    foreach ($key in $inputMap.Keys) {
        $reversedMap[$inputMap[$key]] = $key
    }
    return $reversedMap
}


Export-ModuleMember -Function Get-HistoryCommandRank, Get-ScriptFolder, Start-Ipython, Start-PSReadline, Invoke-FzfHistorySmart, Register-FzfHistorySmartKeyBinding, New-Shortcut, Set-Script, Update-Semver, Get-FormatLength, Get-NeedBinaryDigit, Get-ReversedMap
