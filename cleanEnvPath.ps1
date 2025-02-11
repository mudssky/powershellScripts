<#
.SYNOPSIS
    清理环境变量中无用的路径，比如没有exe的路径
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
    [ValidateSet('Machine', 'User')]
    [string]$EnvTarget = 'User'
)


Import-Module (Resolve-Path -Path $PSScriptRoot/psutils)


$currentPathStr = Get-EnvParam -ParamName 'Path' -EnvTarget $EnvTarget
$currentPathList = ($currentPathStr -split ';') | Where-Object { $_ -ne '' }
Write-Host -ForegroundColor Yellow "current $EnvTarget path:"
$currentPathList | ForEach-Object { Write-Host -ForegroundColor Yellow $_ }

# 创建列表
$needRemovePath = @()
$finalPaths = @()
foreach ($path in   $currentPathList) {
    if (Test-PathHasExe -Path $path ) {
        $finalPaths += $path
    }
    else {
        $needRemovePath += $path
    }
}
Write-host -ForegroundColor Red "need remove path:"
$needRemovePath | ForEach-Object { Write-Host -ForegroundColor Red $_ }

if ($needRemovePath.Count -eq 0) {
    Write-Host -ForegroundColor Green "no need remove path"
    exit 0
}

# 读取用户确认

# Read-Host比较简单
# $confirmation = Read-Host "是否继续执行操作？(输入 yes/no 确认)"
# if ($confirmation -eq 'yes') {
#     Write-Host "用户确认，继续执行..."
#     # 此处添加需要执行的操作
# } else {
#     Write-Host "用户取消操作。"
# }
$title = "操作确认"
$message = "是否执行清理环境变量操作，会重新设置环境变量"
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "确认执行"
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "取消操作"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
$result = $host.UI.PromptForChoice($title, $message, $options, 0)  # 默认选中Yes

if ($result -eq 0) {
    Write-Host "用户确认，继续执行..."
    $finalPaths | ForEach-Object { Write-Host -ForegroundColor Green $_ }
    $fialPathStr = ($finalPaths -join ';')
    Write-Host "设置环境变量 $EnvTarget 的 Path 为 $fialPathStr"
    # 此处添加需要执行的操作
    Set-EnvPath -EnvTarget $EnvTarget -PathStr  $fialPathStr

}
else {
    Write-Host "用户取消操作。"
}


