<#
.SYNOPSIS
    Claude Code 配置管理工具

.DESCRIPTION
    支持部署用户全局配置、初始化项目级配置以及生成项目记忆文件 CLAUDE.md。

.EXAMPLE
    .\Manage-ClaudeConfig.ps1 -Action LoadUserConfig
    部署全局设置。

.EXAMPLE
    .\Manage-ClaudeConfig.ps1 -Action InitProject
    在当前目录初始化项目配置。
#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("LoadUserConfig", "InitProject", "ShowStatus")]
    [string]$Action = "ShowStatus"
)

$TemplateDir = "$PSScriptRoot\config"
$GlobalConfigDir = Join-Path $env:USERPROFILE ".claude"
$GlobalConfigFile = Join-Path $GlobalConfigDir "settings.json"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

# 1. 加载/同步用户全局配置
function Load-UserConfig {
    $SourceFile = Join-Path $TemplateDir "user.settings.json"
    
    if (-not (Test-Path $SourceFile)) {
        throw "模板文件不存在: $SourceFile"
    }

    if (-not (Test-Path $GlobalConfigDir)) {
        New-Item -Path $GlobalConfigDir -ItemType Directory -Force | Out-Null
        Write-Info "创建全局配置目录: $GlobalConfigDir"
    }

    if (Test-Path $GlobalConfigFile) {
        $BackupFile = $GlobalConfigFile + ".bak"
        Copy-Item $GlobalConfigFile $BackupFile -Force
        Write-Info "已备份现有配置到: $BackupFile"
    }

    Copy-Item $SourceFile $GlobalConfigFile -Force
    Write-Success "用户全局配置已部署至: $GlobalConfigFile"
}

# 2. 初始化项目配置
function Initialize-Project {
    $ProjectClaudeDir = Join-Path (Get-Location) ".claude"
    $ProjectSettings = Join-Path $ProjectClaudeDir "settings.json"
    $ProjectMemory = Join-Path (Get-Location) "CLAUDE.md"

    # 创建 .claude 目录
    if (-not (Test-Path $ProjectClaudeDir)) {
        New-Item -Path $ProjectClaudeDir -ItemType Directory -Force | Out-Null
        Write-Info "创建项目配置目录: .claude/"
    }

    # 生成默认项目设置
    $DefaultSettings = @{
        permissions = @{
            allow = @(
                "Read(**/*.{ts,tsx,js,jsx,json,md,yml,yaml})"
                "Bash(npm run test:*)"
                "Bash(npm run lint)"
            )
            deny  = @(
                "Read(.env*)"
                "Read(node_modules/**)"
            )
        }
        sandbox     = @{
            enabled = $true
        }
    } | ConvertTo-Json -Depth 10

    if (-not (Test-Path $ProjectSettings)) {
        $DefaultSettings | Out-File -FilePath $ProjectSettings -Encoding utf8
        Write-Success "已生成项目配置文件: .claude/settings.json"
    }
    else {
        Write-Warning "项目配置文件已存在，跳过生成。"
    }

    # 生成 CLAUDE.md 模板
    if (-not (Test-Path $ProjectMemory)) {
        $ProjectName = (Get-Item .).Name
        $MemoryTemplate = @"
# 项目: $ProjectName

## 🛠 技术栈
- 框架: [填入框架, e.g. Next.js]
- 语言: TypeScript
- 工具: [填入工具, e.g. Tailwind, Zod]

## 📏 代码规范
- 命名: [e.g. PascalCase for components]
- 注释: 使用中文
- 异常处理: 必须使用 try/catch

## 🏗 构建与任务
- Build: `npm run build`
- Test: `npm run test`
- Lint: `npm run lint`

## 📂 核心目录
- src/: 源码
"@
        $MemoryTemplate | Out-File -FilePath $ProjectMemory -Encoding utf8
        Write-Success "已生成项目记忆文件: CLAUDE.md"
    }
    else {
        Write-Warning "CLAUDE.md 已存在，跳过生成。"
    }
}

# 3. 显示状态
function Show-ConfigStatus {
    Write-Host "`n--- Claude Code 配置状态 ---" -ForegroundColor DarkCyan
    
    $GlobalStatus = if (Test-Path $GlobalConfigFile) { "已就绪" } else { "未配置" }
    $GlobalColor = ($GlobalStatus -eq "已就绪") ? "Green" : "Red"
    Write-Host "全局配置 ($GlobalConfigFile): " -NoNewline
    Write-Host $GlobalStatus -ForegroundColor $GlobalColor

    $ProjectClaudeDir = Join-Path (Get-Location) ".claude"
    $ProjectStatus = if (Test-Path $ProjectClaudeDir) { "已初始化" } else { "未初始化" }
    $ProjectColor = ($ProjectStatus -eq "已初始化") ? "Green" : "Yellow"
    Write-Host "当前项目状态: " -NoNewline
    Write-Host $ProjectStatus -ForegroundColor $ProjectColor
    
    $MemoryStatus = if (Test-Path "CLAUDE.md") { "存在" } else { "缺失" }
    $MemoryColor = ($MemoryStatus -eq "存在") ? "Green" : "Yellow"
    Write-Host "项目记忆 (CLAUDE.md): " -NoNewline
    Write-Host $MemoryStatus -ForegroundColor $MemoryColor
    Write-Host "---------------------------`n"
}

# 执行逻辑
switch ($Action) {
    "LoadUserConfig" { Load-UserConfig }
    "InitProject" { Initialize-Project }
    "ShowStatus" { Show-ConfigStatus }
}
