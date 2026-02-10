<#
.SYNOPSIS
    显示当前 Profile 加载的自定义别名、函数和关键环境变量。
#>
function Show-MyProfileHelp {
    [CmdletBinding()]
    param()

    Write-Host "--- PowerShell Profile 帮助 ---" -ForegroundColor Cyan
    Write-Host ("当前模式: {0}" -f $script:ProfileMode) -ForegroundColor DarkCyan

    if (-not $script:ProfileExtendedFeaturesLoaded) {
        Write-Host "`n[功能降级提示]" -ForegroundColor Yellow
        Write-Host "  当前处于 UltraMinimal 模式，已跳过模块/别名/工具等高级功能加载。" -ForegroundColor Gray
        Write-Host "  如需完整能力，请使用以下任一方式后重新加载：" -ForegroundColor Gray
        Write-ProfileModeFallbackGuide
        Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
        return
    }

    # 1. 自定义别名
    Write-Host "`n[自定义别名]" -ForegroundColor Yellow
    Get-CustomAlias -AliasDespPrefix $AliasDescPrefix | Format-Table -AutoSize

    # 2. 自定义函数别名
    Write-Host "`n[自定义函数别名]" -ForegroundColor Yellow
    $script:userAlias |
        Where-Object { $_.PSObject.Properties.Name -contains 'command' } |
        Select-Object @{N = '函数名'; E = 'aliasName' }, @{N = '底层命令'; E = {
                if ($_.PSObject.Properties.Name -contains 'commandArgs' -and $null -ne $_.commandArgs -and @($_.commandArgs).Count -gt 0) {
                    "$($_.command) $((@($_.commandArgs)) -join ' ')"
                }
                else {
                    $_.command
                }
            }
        }, @{N = '描述'; E = 'description' } | Format-Table -AutoSize

    # 3. 自定义函数包装
    $customFunctionWrappers = Get-CustomFunctionWrapperInfos
    Write-Host "`n[自定义函数包装]" -ForegroundColor Yellow
    if ($customFunctionWrappers -and $customFunctionWrappers.Count -gt 0) {
        $customFunctionWrappers | Select-Object @{N = '函数名'; E = 'functionName' }, @{N = '描述'; E = 'description' } | Format-Table -AutoSize
    }
    else {
        Write-Host "  暂无自定义函数包装" -ForegroundColor Gray
    }

    # 4. 核心管理函数
    Write-Host "`n[核心管理函数]" -ForegroundColor Yellow
    "Initialize-Environment", "Show-MyProfileHelp", "Add-CondaEnv" | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Where-Object { $_ } | Format-Table Name, CommandType, Source -AutoSize

    # 5. 关键环境变量
    Write-Host "`n[关键环境变量]" -ForegroundColor Yellow
    $envVars = @(
        'POWERSHELL_SCRIPTS_ROOT',
        'http_proxy',
        'https_proxy',
        'RUSTC_WRAPPER',
        'YAZI_FILE_ONE'
    )
    foreach ($var in $envVars) {
        $valueItem = Get-Item -Path "Env:$var" -ErrorAction SilentlyContinue
        if ($null -ne $valueItem) {
            Write-Host ("{0,-25} : {1}" -f $var, $valueItem.Value)
        }
    }

    # 6. 用户级持久环境变量（仅 Windows 支持）
    if ($IsWindows) {
        Write-Host "`n[用户级持久环境变量]" -ForegroundColor Yellow
        $persistVars = @('POWERSHELL_SCRIPTS_ROOT', 'http_proxy', 'https_proxy')
        foreach ($var in $persistVars) {
            $uval = [Environment]::GetEnvironmentVariable($var, "User")
            if ($uval) { Write-Host ("{0,-25} : {1}" -f "$var(用户级)", $uval) }
        }
    }

    Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
}
