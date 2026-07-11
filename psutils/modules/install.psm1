# 导入操作系统检测模块
$osModulePath = Join-Path $PSScriptRoot "os.psm1"
if (Test-Path $osModulePath) {
    Import-Module $osModulePath -Force
}

$configModulePath = Join-Path $PSScriptRoot "config.psm1"
if (-not (Get-Command ConvertTo-ConfigHashtable -ErrorAction SilentlyContinue) -and (Test-Path $configModulePath)) {
    Import-Module $configModulePath -Force
}

if (-not $script:ModuleInstalledCache) {
    $script:ModuleInstalledCache = @{}
}

function Invoke-InstallModuleCommand {
    <#
    .SYNOPSIS
        执行模块安装命令。
    .DESCRIPTION
        将外部 `Install-Module` 调用收口到模块内包装函数，便于测试稳定 mock，
        同时避免测试意外触发真实 PowerShell Gallery 路径。
    .PARAMETER ModuleName
        要安装的模块名称。
    .OUTPUTS
        None。安装失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
}

function Import-InstalledModule {
    <#
    .SYNOPSIS
        导入已安装模块。
    .DESCRIPTION
        将外部 `Import-Module` 调用收口到模块内包装函数，便于测试稳定 mock，
        避免测试阶段回退到真实模块解析链路。
    .PARAMETER ModuleName
        要导入的模块名称。
    .PARAMETER ImportErrorAction
        导入失败时的错误策略。
    .OUTPUTS
        None。导入结果写入当前 PowerShell 会话。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter()]
        [System.Management.Automation.ActionPreference]$ImportErrorAction = [System.Management.Automation.ActionPreference]::Continue
    )

    Import-Module $ModuleName -ErrorAction $ImportErrorAction
}

function Find-InstalledModulePath {
    <#
    .SYNOPSIS
        在 PSModulePath 中查找模块入口文件。
    .DESCRIPTION
        优先使用目录与清单文件直查，避免 `Get-Module -ListAvailable` 的全量发现开销。
        该函数只负责返回首个命中的模块入口路径；未命中时返回 `$null`。
    .PARAMETER ModuleName
        要查找的模块名称。
    .OUTPUTS
        [string] 模块入口文件路径；未找到时返回 `$null`。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($ModuleName)) {
        return $null
    }

    $loadedModule = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($loadedModule) {
        return $loadedModule.Path
    }

    $moduleRoots = $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($moduleRoot in $moduleRoots) {
        $trimmedRoot = $moduleRoot.Trim()
        if (-not (Test-Path -LiteralPath $trimmedRoot -PathType Container)) {
            continue
        }

        foreach ($directCandidate in @(
                (Join-Path $trimmedRoot "$ModuleName.psd1"),
                (Join-Path $trimmedRoot "$ModuleName.psm1")
            )) {
            if (Test-Path -LiteralPath $directCandidate -PathType Leaf) {
                return $directCandidate
            }
        }

        $moduleDirectory = Join-Path $trimmedRoot $ModuleName
        if (-not (Test-Path -LiteralPath $moduleDirectory -PathType Container)) {
            continue
        }

        foreach ($moduleCandidate in @(
                (Join-Path $moduleDirectory "$ModuleName.psd1"),
                (Join-Path $moduleDirectory "$ModuleName.psm1")
            )) {
            if (Test-Path -LiteralPath $moduleCandidate -PathType Leaf) {
                return $moduleCandidate
            }
        }

        foreach ($versionDirectory in @(Get-ChildItem -LiteralPath $moduleDirectory -Directory -ErrorAction SilentlyContinue)) {
            foreach ($versionCandidate in @(
                    (Join-Path $versionDirectory.FullName "$ModuleName.psd1"),
                    (Join-Path $versionDirectory.FullName "$ModuleName.psm1")
                )) {
                if (Test-Path -LiteralPath $versionCandidate -PathType Leaf) {
                    return $versionCandidate
                }
            }
        }
    }

    return $null
}

function Test-ModuleInstalled {
    <#
    .SYNOPSIS
        检测指定的PowerShell模块是否已安装
    .DESCRIPTION
        检查指定的PowerShell模块是否在系统中可用
    .PARAMETER ModuleName
        要检测的模块名称
    .EXAMPLE
        Test-ModuleInstalled -ModuleName "Pester"
        检测Pester模块是否已安装
    .EXAMPLE
        if (Test-ModuleInstalled "PSReadLine") {
            Write-Host "PSReadLine已安装"
        }
    .OUTPUTS
        [bool] 如果模块已安装返回$true，否则返回$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    try {
        if ($script:ModuleInstalledCache.ContainsKey($ModuleName)) {
            return $script:ModuleInstalledCache[$ModuleName]
        }

        $modulePath = Find-InstalledModulePath -ModuleName $ModuleName
        $isInstalled = -not [string]::IsNullOrWhiteSpace($modulePath)
        $script:ModuleInstalledCache[$ModuleName] = $isInstalled
        
        Write-Verbose "模块 '$ModuleName' 安装状态: $isInstalled"
        return $isInstalled
    }
    catch {
        Write-Warning "检测模块 '$ModuleName' 时发生错误: $_"
        return $false
    }
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        安装所需的PowerShell模块
    .DESCRIPTION
        检查并安装指定的PowerShell模块，如果模块已存在则直接导入
    .PARAMETER ModuleNames
        要确保可用的模块名称数组。

    .EXAMPLE
        Install-RequiredModule -ModuleNames @("Pester", "PSReadLine")
        安装Pester和PSReadLine模块

    .OUTPUTS
        PSCustomObject[]。包含 Name、Status、ExitCode 与 Message。
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames
    )
    
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($module in $ModuleNames) {
        $status = ''
        $exitCode = 0
        $message = ''
        if (-not (Test-ModuleInstalled -ModuleName $module)) {
            try {
                if (-not $PSCmdlet.ShouldProcess($module, '安装 PowerShell 模块')) {
                    $status = if ($WhatIfPreference) { 'Preview' } else { 'Skipped' }
                    $message = if ($WhatIfPreference) { '预览模块安装' } else { '用户跳过模块安装' }
                }
                else {
                    Write-Host "正在安装 $module 模块..." -ForegroundColor Yellow
                    Invoke-InstallModuleCommand -ModuleName $module
                    Import-InstalledModule -ModuleName $module -ImportErrorAction Stop
                    $script:ModuleInstalledCache[$module] = $true
                    $status = 'Installed'
                    $message = '模块安装并导入成功'
                }
            }
            catch {
                $status = 'Failed'
                $exitCode = 1
                $message = $_.Exception.Message
                Write-Warning "无法安装 $module 模块: $message"
            }
        }
        else {
            Write-Verbose "模块 $module 已安装，正在导入..."
            Import-InstalledModule -ModuleName $module -ImportErrorAction SilentlyContinue
            $status = 'AlreadyPresent'
            $message = '模块已安装'
        }

        $results.Add([pscustomobject]@{
                Name     = $module
                Status   = $status
                ExitCode = $exitCode
                Message  = $message
            })
    }

    return $results.ToArray()
}


function Test-AppFilter {
    <#
    .SYNOPSIS
        测试应用信息是否满足过滤条件
    .DESCRIPTION
        基于脚本块回调函数测试应用信息是否满足指定的过滤条件
    .PARAMETER AppInfo
        要测试的应用信息对象
    .PARAMETER Predicates
        过滤谓词脚本块数组
    .PARAMETER Mode
        过滤模式：'And' 表示所有条件都必须满足，'Or' 表示任一条件满足即可
    .EXAMPLE
        $filter = { param($app) $app.supportOs -contains "Linux" }
        Test-AppFilter -AppInfo $appInfo -Predicates $filter
    .OUTPUTS
        [bool] 如果满足过滤条件返回 $true，否则返回 $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AppInfo,
        
        [Parameter(Mandatory = $true)]
        [ScriptBlock[]]$Predicates,
        
        [Parameter()]
        [ValidateSet("And", "Or")]
        [string]$Mode = "And"
    )
    
    if (-not $Predicates -or $Predicates.Count -eq 0) {
        return $true
    }
    
    $results = foreach ($predicate in $Predicates) {
        try {
            $result = & $predicate $AppInfo
            if ($null -eq $result) {
                Write-Warning "过滤函数返回 null，视为 false"
                $false
            } else {
                [bool]$result
            }
        }
        catch {
            Write-Warning "过滤函数执行失败: $($_.Exception.Message)"
            $false
        }
    }
    
    if ($Mode -eq "And") {
        return $results -notcontains $false
    } else {
        return $results -contains $true
    }
}

function Get-PackageManagerAppTags {
    <#
    .SYNOPSIS
        返回规范化的小写应用标签。

    .PARAMETER AppInfo
        应用配置对象。

    .OUTPUTS
        System.String[]。去除空值后的标签数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppInfo
    )

    return @($AppInfo.tag | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Select-PackageManagerApps {
    <#
    .SYNOPSIS
        按操作系统和标签选择包管理器应用。

    .DESCRIPTION
        该函数只执行纯筛选，不检测或安装软件。RequiredTag 必须全部命中，AnyTag
        至少命中一个，ExcludedTag 任一命中即排除；skipInstall 默认始终优先排除。

    .PARAMETER Apps
        待筛选的应用配置数组。

    .PARAMETER TargetOS
        可选目标操作系统。未传时不做操作系统筛选。

    .PARAMETER RequiredTag
        必须全部包含的标签。

    .PARAMETER AnyTag
        至少包含一个的标签。

    .PARAMETER ExcludedTag
        任一命中即排除的标签。

    .PARAMETER IncludeSkipped
        为生成结构化 Skipped 结果保留 skipInstall 条目；不会改变其跳过语义。

    .OUTPUTS
        System.Object[]。保持原配置顺序的应用对象数组。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Apps,

        [ValidateSet('', 'Windows', 'Linux', 'macOS')]
        [string]$TargetOS = '',

        [string[]]$RequiredTag,

        [string[]]$AnyTag,

        [string[]]$ExcludedTag,

        [switch]$IncludeSkipped
    )

    $requiredTags = @($RequiredTag | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $anyTags = @($AnyTag | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $excludedTags = @($ExcludedTag | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })

    return @($Apps | Where-Object {
            $app = $_
            if (-not $IncludeSkipped -and [bool]$app.skipInstall) {
                return $false
            }
            if ($TargetOS -and $app.supportOs -and $TargetOS -notin @($app.supportOs)) {
                return $false
            }

            $tags = @(Get-PackageManagerAppTags -AppInfo $app)
            if (@($requiredTags | Where-Object { $_ -notin $tags }).Count -gt 0) {
                return $false
            }
            if ($anyTags.Count -gt 0 -and @($anyTags | Where-Object { $_ -in $tags }).Count -eq 0) {
                return $false
            }
            if (@($excludedTags | Where-Object { $_ -in $tags }).Count -gt 0) {
                return $false
            }
            return $true
        })
}

function Test-PackageManagerAppCatalog {
    <#
    .SYNOPSIS
        校验应用清单中的预设和类别标签。

    .PARAMETER ConfigObject
        包含 packageManagers 的应用配置对象。

    .PARAMETER AllowedTag
        允许使用的标签集合；默认包含仓库现有场景、预设、类别与可选组标签。

    .OUTPUTS
        System.Boolean。校验通过返回 true，失败时抛出包含包管理器和应用名的异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ConfigObject,

        [string[]]$AllowedTag = @(
            'linuxserver', 'macbook', 'aicoding',
            'core', 'full',
            'cli', 'font', 'gui', 'platform',
            'terminal-extras', 'ai-cli'
        )
    )

    $config = ConvertTo-ConfigHashtable -InputObject $ConfigObject
    if (-not $config.ContainsKey('packageManagers')) {
        throw '应用配置缺少 packageManagers'
    }
    $packageManagers = ConvertTo-ConfigHashtable -InputObject $config.packageManagers

    $allowedTags = @($AllowedTag | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $categoryTags = @('cli', 'font', 'gui', 'platform')
    foreach ($packageManager in @($packageManagers.Keys)) {
        foreach ($app in @($packageManagers[$packageManager])) {
            $appName = [string]$app.name
            if ([string]::IsNullOrWhiteSpace($appName)) {
                throw "包管理器 $packageManager 包含缺少 name 的应用配置"
            }

            $tags = @(Get-PackageManagerAppTags -AppInfo $app)
            if (@($tags | Select-Object -Unique).Count -ne $tags.Count) {
                throw "应用 $packageManager/$appName 包含重复标签"
            }
            foreach ($tag in $tags) {
                if ($tag -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or $tag -notin $allowedTags) {
                    throw "应用 $packageManager/$appName 包含未知标签: $tag"
                }
            }
            if ('core' -in $tags -and 'full' -in $tags) {
                throw "应用 $packageManager/$appName 不能同时标记 core 和 full"
            }
            if ('core' -in $tags -or 'full' -in $tags) {
                $categories = @($categoryTags | Where-Object { $_ -in $tags })
                if ($categories.Count -ne 1) {
                    throw "预设应用 $packageManager/$appName 必须且只能包含一个类别标签"
                }
            }
        }
    }

    return $true
}

function ConvertFrom-PackageInstallCommand {
    <#
    .SYNOPSIS
        把受限的单条原生命令解析为参数数组。

    .DESCRIPTION
        仅接受命令、命令参数和字符串 token，拒绝管道、重定向、变量和语句分隔符，
        防止仓库配置中的展示字符串通过 Invoke-Expression 执行额外语义。

    .PARAMETER Command
        应用配置中的安装命令。

    .OUTPUTS
        PSCustomObject。Executable 为命令名，ArgumentList 为字符串参数数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $parseErrors = $null
    $tokens = @([System.Management.Automation.PSParser]::Tokenize($Command, [ref]$parseErrors))
    if (@($parseErrors).Count -gt 0 -or $tokens.Count -eq 0) {
        throw "安装命令无法解析: $Command"
    }

    $allowedTokenTypes = @('Command', 'CommandArgument', 'CommandParameter', 'String')
    $unsupportedToken = $tokens | Where-Object { [string]$_.Type -notin $allowedTokenTypes } | Select-Object -First 1
    if ($unsupportedToken) {
        throw "安装命令包含不支持的语法 $($unsupportedToken.Type): $Command"
    }

    $parts = @($tokens | ForEach-Object { [string]$_.Content })
    return [pscustomobject]@{
        Executable   = $parts[0]
        ArgumentList = @($parts | Select-Object -Skip 1)
    }
}

function Invoke-PackageInstallCommand {
    <#
    .SYNOPSIS
        使用参数数组执行应用安装命令。

    .PARAMETER Command
        受限的单条原生命令字符串。

    .OUTPUTS
        System.Int32。原生命令退出码；执行失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $parsed = ConvertFrom-PackageInstallCommand -Command $Command
    $commandInfo = Get-Command $parsed.Executable -ErrorAction Stop
    & $commandInfo.Source @($parsed.ArgumentList)
    $exitCode = [int]$LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "安装命令退出码为 ${exitCode}: $Command"
    }
    return $exitCode
}

function Test-PackageManagerAppInstalled {
    <#
    .SYNOPSIS
        通过共享应用检测能力判断应用是否已安装。

    .PARAMETER AppName
        CLI 或应用检测名称。

    .PARAMETER FilterCli
        是否只检测命令行程序。

    .OUTPUTS
        System.Boolean。已安装返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [switch]$FilterCli
    )

    return [bool](Test-ApplicationInstalled -AppName $AppName -FilterCli:$FilterCli)
}

function Install-PackageManagerApps {
    <#
    .SYNOPSIS
        根据统一应用清单筛选并安装指定包管理器的应用。

    .DESCRIPTION
        保留 ConfigPath、ConfigObject 和 predicate 兼容参数；新增标签筛选与逐项结构化结果。
        单项失败不会中止同一步其他应用，调用方可通过 Required 与 Failed 状态决定步骤退出码。

    .PARAMETER PackageManager
        包管理器名称，如 homebrew、choco、scoop。

    .PARAMETER ConfigObject
        配置对象，与 ConfigPath 二选一。

    .PARAMETER ConfigPath
        JSON 配置路径。

    .PARAMETER FilterByOS
        是否按目标操作系统筛选。

    .PARAMETER TargetOS
        Windows、Linux 或 macOS；未指定时自动检测。

    .PARAMETER FilterPredicate
        兼容的单个自定义过滤脚本块。

    .PARAMETER FilterPredicates
        兼容的多个自定义过滤脚本块。

    .PARAMETER FilterMode
        多 predicate 的 And 或 Or 组合方式。

    .PARAMETER RequiredTag
        必须全部包含的标签。

    .PARAMETER AnyTag
        至少包含一个的标签。

    .PARAMETER ExcludedTag
        任一命中即排除的标签。

    .PARAMETER Required
        标记本次候选为步骤必需项，供调用方汇总失败。

    .OUTPUTS
        PSCustomObject[]。字段包含 Name、PackageManager、Status、ExitCode、Message、Required 和 Command。
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ConfigPath')]
    param(
        [Parameter(Mandatory)]
        [string]$PackageManager,

        [Parameter(Mandatory, ParameterSetName = 'ConfigObject')]
        [object]$ConfigObject,

        [Parameter(ParameterSetName = 'ConfigPath')]
        [string]$ConfigPath = "$PSScriptRoot/apps-config.json",

        [bool]$FilterByOS = $true,

        [ValidateSet('Windows', 'Linux', 'macOS')]
        [string]$TargetOS,

        [ScriptBlock]$FilterPredicate,

        [ScriptBlock[]]$FilterPredicates,

        [ValidateSet('And', 'Or')]
        [string]$FilterMode = 'And',

        [string[]]$RequiredTag,

        [string[]]$AnyTag,

        [string[]]$ExcludedTag,

        [switch]$Required
    )

    if ($FilterByOS -and [string]::IsNullOrWhiteSpace($TargetOS)) {
        $TargetOS = Get-OperatingSystem
        Write-Verbose "自动检测到当前操作系统: $TargetOS"
    }

    $config = if ($PSCmdlet.ParameterSetName -eq 'ConfigObject') {
        ConvertTo-ConfigHashtable -InputObject $ConfigObject
    }
    else {
        (Resolve-ConfigSources -Sources @(
                @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = $ConfigPath }
            ) -BasePath (Get-Location).Path -ErrorOnMissing).Values
    }
    $packageManagers = if ($config.ContainsKey('packageManagers')) {
        ConvertTo-ConfigHashtable -InputObject $config.packageManagers
    }
    else {
        @{}
    }

    if (-not $packageManagers.ContainsKey($PackageManager)) {
        Write-Warning "未找到 $PackageManager 的应用配置"
        return
    }

    $selectionParameters = @{
        Apps           = @($packageManagers[$PackageManager])
        RequiredTag    = $RequiredTag
        AnyTag         = $AnyTag
        ExcludedTag    = $ExcludedTag
        IncludeSkipped = $true
    }
    if ($FilterByOS) {
        $selectionParameters.TargetOS = $TargetOS
    }
    $installList = @(Select-PackageManagerApps @selectionParameters)

    if ($FilterPredicate -or $FilterPredicates) {
        $predicates = @()
        if ($FilterPredicate) {
            $predicates += $FilterPredicate
        }
        if ($FilterPredicates) {
            $predicates += $FilterPredicates
        }
        $installList = @($installList | Where-Object {
                Test-AppFilter -AppInfo ([pscustomobject]$_) -Predicates $predicates -Mode $FilterMode
            })
    }

    if ($installList.Count -eq 0) {
        Write-Warning "没有找到符合条件的 $PackageManager 应用"
        return
    }

    $results = [System.Collections.Generic.List[object]]::new()
    Write-Host "开始检查 $PackageManager 应用..." -ForegroundColor Green
    foreach ($appInfo in $installList) {
        $appName = [string]$appInfo.name
        $cliName = if ($appInfo.cliName) { [string]$appInfo.cliName } else { $appName }
        $command = Get-PackageInstallCommand -PackageManager $PackageManager -AppName $appName -CustomCommand ([string]$appInfo.command)
        $status = ''
        $exitCode = 0
        $message = ''

        if ([bool]$appInfo.skipInstall) {
            $status = 'Skipped'
            $message = '配置标记 skipInstall'
        }
        elseif ([string]::IsNullOrWhiteSpace($command)) {
            $status = 'Failed'
            $exitCode = 2
            $message = "不支持的包管理器或安装命令为空: $PackageManager"
        }
        else {
            try {
                $isInstalled = Test-PackageManagerAppInstalled -AppName $cliName -FilterCli:([bool]$appInfo.filterCli)
                if ($isInstalled) {
                    $status = 'AlreadyPresent'
                    $message = '应用已安装'
                }
                elseif (-not $PSCmdlet.ShouldProcess($appName, '安装应用')) {
                    $status = if ($WhatIfPreference) { 'Preview' } else { 'Skipped' }
                    $message = if ($WhatIfPreference) { '预览安装命令' } else { '用户跳过安装' }
                }
                else {
                    Write-Host "正在安装 $appName..." -ForegroundColor Yellow
                    $null = Invoke-PackageInstallCommand -Command $command
                    $status = 'Installed'
                    $message = '安装完成'
                }
            }
            catch {
                $status = 'Failed'
                $exitCode = 1
                $message = $_.Exception.Message
                Write-Warning "安装 $appName 失败: $message"
            }
        }

        $results.Add([pscustomobject]@{
                Name           = $appName
                PackageManager = $PackageManager
                Status         = $status
                ExitCode       = $exitCode
                Message        = $message
                Required       = [bool]$Required
                Command        = $command
            })
    }

    return $results.ToArray()
}

function Install-ExecutableFile {
    <#
    .SYNOPSIS
        将可执行文件安装到目标目录。

    .DESCRIPTION
        创建目标目录、复制源文件，并可在非 Windows 平台设置执行权限。若启用
        `NoOverwrite` 且目标文件已存在，则返回 Skipped 状态而不覆盖文件。

    .PARAMETER SourcePath
        源可执行文件路径。

    .PARAMETER InstallDirectory
        目标安装目录。

    .PARAMETER ExecutableName
        安装后的文件名。

    .PARAMETER OperatingSystem
        目标平台操作系统，支持 `windows`、`linux`、`macos`；非 Windows 时尝试 `chmod +x`。

    .PARAMETER NoOverwrite
        目标文件已存在时跳过安装。

    .OUTPUTS
        PSCustomObject
        返回包含 `Status` 与 `Path` 的安装结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$InstallDirectory,

        [Parameter(Mandatory)]
        [string]$ExecutableName,

        [ValidateSet('windows', 'linux', 'macos')]
        [string]$OperatingSystem = $(if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }),

        [switch]$NoOverwrite
    )

    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    $targetPath = Join-Path $InstallDirectory $ExecutableName
    if ($NoOverwrite -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status = 'Skipped'
            Path   = $targetPath
        }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
    if ($OperatingSystem -ne 'windows') {
        $chmodCommand = Get-Command chmod -ErrorAction SilentlyContinue
        if ($chmodCommand) {
            & $chmodCommand.Source '+x' $targetPath
        }
    }

    return [pscustomobject]@{
        Status = 'Installed'
        Path   = $targetPath
    }
}

function Get-PackageInstallCommand {
    <#
    .SYNOPSIS
        根据包管理器和应用名称生成安装命令
    .DESCRIPTION
        根据指定的包管理器类型和应用名称，生成对应的安装命令。
        如果提供了自定义命令，则优先使用自定义命令。
    .PARAMETER PackageManager
        包管理器名称，支持：choco、scoop、winget、cargo、homebrew、apt
    .PARAMETER AppName
        要安装的应用名称
    .PARAMETER CustomCommand
        自定义安装命令（可选）
    .EXAMPLE
        Get-PackageInstallCommand -PackageManager "scoop" -AppName "git"
        返回: "scoop install git"
    .EXAMPLE
        Get-PackageInstallCommand -PackageManager "choco" -AppName "nodejs" -CustomCommand "choco install nodejs.install -y"
        返回: "choco install nodejs.install -y"
    .OUTPUTS
        [string] 安装命令字符串，如果包管理器不支持则返回 $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageManager,
        
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter()]
        [string]$CustomCommand
    )
    
    # 如果提供了自定义命令，优先使用
    if ($CustomCommand) {
        return $CustomCommand
    }
    
    # 根据包管理器生成默认安装命令
    switch ($PackageManager.ToLower()) {
        'choco' { return "choco install $AppName -y" }
        'scoop' { return "scoop install $AppName" }
        'winget' { return "winget install $AppName" }
        'cargo' { return "cargo install $AppName" }
        'homebrew' { return "brew install $AppName" }
        'apt' { return "apt install $AppName" }
        default { 
            Write-Verbose "不支持的包管理器: $PackageManager"
            return $null
        }
    }
}

Export-ModuleMember -Function @(
    'Test-ModuleInstalled'
    'Install-RequiredModule'
    'Select-PackageManagerApps'
    'Test-PackageManagerAppCatalog'
    'Install-PackageManagerApps'
    'Install-ExecutableFile'
    'Get-PackageInstallCommand'
)
