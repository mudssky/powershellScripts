# 导入psutils模块以使用管理员权限检测功能
Import-Module "$PSScriptRoot\psutils" -Force

# 检查管理员权限
if (-not (Test-Administrator)) {
    Write-Warning "检测到当前未以管理员权限运行"
    Write-Host "某些操作（如创建符号链接）可能需要管理员权限" -ForegroundColor Yellow
    Write-Host "如果遇到权限错误，请以管理员身份重新运行此脚本" -ForegroundColor Yellow
    
    # 询问用户是否继续
    $continue = Read-Host "是否继续执行脚本？(y/N)"
    if ($continue -notmatch '^[Yy]') {
        Write-Host "脚本已取消执行" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "已检测到管理员权限" -ForegroundColor Green
}

# 安装测试框架
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "正在安装 Pester 模块..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force
    Write-Host "Pester 模块安装完成" -ForegroundColor Green
} else {
    Write-Host "Pester 模块已安装，跳过安装" -ForegroundColor Green
}


$traeRulesFilePath = "$PSScriptRoot/.trae/rules/project_rules.md"
$lingmaRulesFilePath = "$PSScriptRoot/.lingma/rules/project_rules.md"
# 软连接不存在时创建
if (-not (Test-Path -Path $lingmaRulesFilePath)) {
    New-Item -ItemType SymbolicLink -Path $lingmaRulesFilePath -Target $traeRulesFilePath
}


# 载入配置文件
./profile/profile.ps1 -loadProfile