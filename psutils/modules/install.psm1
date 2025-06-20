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



Export-ModuleMember -Function *