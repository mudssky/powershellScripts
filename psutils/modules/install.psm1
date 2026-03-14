# 导入操作系统检测模块
$osModulePath = Join-Path $PSScriptRoot "os.psm1"
if (Test-Path $osModulePath) {
    Import-Module $osModulePath -Force
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
    .PARAMETER ErrorAction
        导入失败时的错误策略。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter()]
        [System.Management.Automation.ActionPreference]$ErrorAction = [System.Management.Automation.ActionPreference]::Continue
    )

    Import-Module $ModuleName -ErrorAction $ErrorAction
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
        要安装的模块名称数组
    .EXAMPLE
        Install-RequiredModule -ModuleNames @("Pester", "PSReadLine")
        安装Pester和PSReadLine模块
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames
    )
    
    foreach ($module in $ModuleNames) {
        if (-not (Test-ModuleInstalled -ModuleName $module)) {
            try {
                Write-Host "正在安装 $module 模块..." -ForegroundColor Yellow
                Invoke-InstallModuleCommand -ModuleName $module
                Import-InstalledModule -ModuleName $module -ErrorAction Stop
                Write-Host "$module 模块安装成功!" -ForegroundColor Green
            }
            catch {
                Write-Warning "无法安装 $module 模块: $_"
            }
        }
        else {
            Write-Verbose "模块 $module 已安装，正在导入..."
            Import-InstalledModule -ModuleName $module -ErrorAction SilentlyContinue
        }
    }
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

function Install-PackageManagerApps() {
    <#
    .SYNOPSIS
        根据配置文件安装指定包管理器的应用程序
    .DESCRIPTION
        从配置文件中读取指定包管理器的应用列表，并根据条件过滤后批量安装应用程序。
        支持操作系统过滤、自定义函数过滤等多种筛选方式。
    .PARAMETER PackageManager
        包管理器名称（如：homebrew, choco, scoop）
    .PARAMETER ConfigObject
        配置对象（与 ConfigPath 二选一）
    .PARAMETER ConfigPath
        配置文件路径，默认为 "$PSScriptRoot/apps-config.json"
    .PARAMETER FilterByOS
        是否按操作系统筛选，默认为 $true
    .PARAMETER TargetOS
        目标操作系统（Windows, Linux, macOS），未指定时自动检测
    .PARAMETER FilterPredicate
        单个过滤脚本块，用于自定义过滤逻辑
    .PARAMETER FilterPredicates
        多个过滤脚本块数组，与 FilterMode 配合使用
    .PARAMETER FilterMode
        过滤模式："And" 表示所有条件都必须满足，"Or" 表示任一条件满足即可，默认为 "And"
    .EXAMPLE
        # 基础用法 - 安装所有适用于当前系统的 homebrew 应用
        Install-PackageManagerApps -PackageManager "homebrew"
    .EXAMPLE
        # 使用自定义过滤器 - 只安装带有 linuxserver 标签的应用
        $linuxServerFilter = { param($app) $app.tag -and "linuxserver" -in $app.tag }
        Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicate $linuxServerFilter
    .EXAMPLE
        # 使用多过滤器 - 安装开发工具或 Git 相关工具
        $filters = @(
            { param($app) $app.tag -contains "development" },
            { param($app) $app.name -like "*git*" }
        )
        Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicates $filters -FilterMode "Or"
    .EXAMPLE
        # 复杂业务逻辑过滤
        $businessFilter = {
            param($app)
            $isLinuxCompatible = $app.supportOs -contains "Linux"
            $notSkipped = -not $app.skipInstall
            $isServerTool = $app.tag -and "linuxserver" -in $app.tag
            
            return $isLinuxCompatible -and $notSkipped -and $isServerTool
        }
        Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicate $businessFilter
    .INPUTS
        None. 此函数不接受管道输入。
    .OUTPUTS
        None. 此函数不返回输出。
    .NOTES
        过滤脚本块接收一个参数 $app，代表应用信息对象，包含以下属性：
        - name: 应用名称
        - cliName: CLI 命令名称
        - description: 应用描述
        - command: 安装命令
        - supportOs: 支持的操作系统数组
        - skipInstall: 是否跳过安装
        - tag: 标签数组
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageManager,
		
        [Parameter(Mandatory, ParameterSetName = 'ConfigObject')]
        [PSCustomObject]$ConfigObject,
		
        [Parameter(ParameterSetName = 'ConfigPath')]
        [string]$ConfigPath = "$PSScriptRoot/apps-config.json",
        
        [Parameter()]
        [bool]$FilterByOS = $true,
        
        [Parameter()]
        [ValidateSet("Windows", "Linux", "macOS")]
        [string]$TargetOS,
        
        [Parameter()]
        [ScriptBlock]$FilterPredicate,
        
        [Parameter()]
        [ScriptBlock[]]$FilterPredicates,
        
        [Parameter()]
        [ValidateSet("And", "Or")]
        [string]$FilterMode = "And"
    )
	
    # 获取目标操作系统
    if ($FilterByOS) {
        if ([string]::IsNullOrWhiteSpace($TargetOS)) {
            # 如果未指定目标操作系统，则使用当前操作系统
            $TargetOS = Get-OperatingSystem
            Write-Verbose "自动检测到当前操作系统: $TargetOS"
        }
        else {
            Write-Verbose "使用指定的目标操作系统: $TargetOS"
        }
    }
    
    # 根据参数集确定安装列表
    if ($PSCmdlet.ParameterSetName -eq 'ConfigObject') {
        $InstallList = $ConfigObject.packageManagers.$PackageManager
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ConfigPath') {
        if (-not (Test-Path $ConfigPath)) {
            Write-Error "配置文件不存在: $ConfigPath"
            return
        }
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        $InstallList = $config.packageManagers.$PackageManager
    }
	
    if (-not $InstallList) {
        Write-Warning "未找到 $PackageManager 的应用配置"
        return
    }
    
    # 根据操作系统筛选应用
    if ($FilterByOS) {
        $originalCount = @($InstallList).Count
        $InstallList = $InstallList | Where-Object {
            # 如果应用没有 supportOs 字段，则不进行筛选
            if (-not $_.supportOs) {
                return $true
            }
            # 检查当前操作系统是否在支持列表中
            return $_.supportOs -contains $TargetOS
        }
        
        $filteredCount = @($InstallList).Count
        Write-Verbose "操作系统筛选: 原始应用数量 $originalCount，筛选后应用数量 $filteredCount"
        
        if ($filteredCount -eq 0) {
            Write-Warning "经过操作系统筛选后，没有找到适用于 $TargetOS 的 $PackageManager 应用"
            return
        }
    }
    
    # 应用自定义过滤器
    if ($FilterPredicate -or $FilterPredicates) {
        $predicates = @()
        if ($FilterPredicate) { $predicates += $FilterPredicate }
        if ($FilterPredicates) { $predicates += $FilterPredicates }
        
        $originalCount = @($InstallList).Count
        $InstallList = $InstallList | Where-Object {
            Test-AppFilter -AppInfo $_ -Predicates $predicates -Mode $FilterMode
        }
        
        $filteredCount = @($InstallList).Count
        Write-Verbose "自定义过滤器筛选: 原始应用数量 $originalCount，筛选后应用数量 $filteredCount"
        
        if ($filteredCount -eq 0) {
            Write-Warning "经过自定义过滤器筛选后，没有找到符合条件的 $PackageManager 应用"
            return
        }
    }
	
    Write-Host "开始检查 $PackageManager 应用..." -ForegroundColor Green
	
    foreach ($appInfo in $InstallList) {
        # 获取应用基本信息
        $appName = $appInfo.name
        $cliName = if ($appInfo.cliName) { $appInfo.cliName } else { $appInfo.name }
		
        # 生成安装命令（如果未配置则根据包管理器自动生成）
        $command = Get-PackageInstallCommand -PackageManager $PackageManager -AppName $appName -CustomCommand $appInfo.command
        if (-not $command) {
            Write-Warning "未知的包管理器: $PackageManager，跳过 $appName"
            continue
        }
		
        # 检查是否跳过安装
        if ($appInfo.skipInstall) {
            Write-Host "跳过安装 $appName" -ForegroundColor Gray
            continue
        }
        
        # 执行安装逻辑
        try {
            # 检查应用是否已安装（使用更智能的检测方法）
            $isInstalled = if ($appInfo.filterCli) {
                # 如果配置中指定仅检测CLI，则只检测命令行程序
                Test-ApplicationInstalled -AppName $cliName -FilterCli $true
            }
            else {
                # 默认检测所有类型（命令行和应用程序）
                Test-ApplicationInstalled -AppName $cliName
            }
            
            if (-not $isInstalled) {
                if ($PSCmdlet.ShouldProcess($appName, "安装应用")) {
                    Write-Host "正在安装 $appName..." -ForegroundColor Yellow
                    Invoke-Expression $command
                    Write-Host "✓ $appName 安装完成" -ForegroundColor Green
                }
            }
            else {
                Write-Host "✓ $appName 已安装" -ForegroundColor Gray
            }
        }
        catch {
            Write-Error "安装 $appName 失败: $($_.Exception.Message)"
        }
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

Export-ModuleMember -Function Test-ModuleInstalled, Install-RequiredModule, Install-PackageManagerApps, Get-PackageInstallCommand
