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
        $module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
        $isInstalled = $null -ne $module
        
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
                Install-Module -Name $module -Scope CurrentUser -Force -ErrorAction Stop
                Import-Module $module -ErrorAction Stop
                Write-Host "$module 模块安装成功!" -ForegroundColor Green
            }
            catch {
                Write-Warning "无法安装 $module 模块: $_"
            }
        }
        else {
            Write-Verbose "模块 $module 已安装，正在导入..."
            Import-Module $module -ErrorAction SilentlyContinue
        }
    }
}


<#
.SYNOPSIS
    通过指定的包管理器批量安装应用程序

.DESCRIPTION
    此函数支持通过多种包管理器（如 Chocolatey、Scoop、Winget、Cargo、Homebrew、APT）
    批量安装应用程序。支持从配置文件或配置对象中读取应用列表，并自动生成安装命令。

.PARAMETER PackageManager
    包管理器名称，支持：choco、scoop、winget、cargo、homebrew、apt

.PARAMETER ConfigObject
    包含应用配置的 PSCustomObject 对象

.PARAMETER ConfigPath
    配置文件路径，默认为 "$PSScriptRoot/apps-config.json"
    配置文件格式参考：/Users/mudssky/projects/powershellScripts/profile/installer/apps-config.json

.EXAMPLE
    Install-PackageManagerApps -PackageManager "scoop" -ConfigPath "./apps-config.json"
    从配置文件安装 Scoop 应用

.EXAMPLE
    Install-PackageManagerApps -PackageManager "choco" -ConfigObject $configObj
    从配置对象安装 Chocolatey 应用

.NOTES
    配置文件格式示例：
    {
      "packageManagers": {
        "scoop": [
          {
            "name": "git",
            "cliName": "git",
            "description": "版本控制系统",
            "command": "scoop install git",
            "skipInstall": false
          }
        ]
      }
    }
    
    字段说明：
    - name: 应用名称（必需）
    - cliName: 命令行名称（可选，默认使用 name）
    - description: 应用描述（可选）
    - command: 安装命令（可选，未配置时自动生成）
    - skipInstall: 是否跳过安装（可选，默认 false）
#>
function Install-PackageManagerApps() {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageManager,
		
        [Parameter(Mandatory, ParameterSetName = 'ConfigObject')]
        [PSCustomObject]$ConfigObject,
		
        [Parameter(ParameterSetName = 'ConfigPath')]
        [string]$ConfigPath = "$PSScriptRoot/apps-config.json"
    )
	
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