<#
.SYNOPSIS
    为VSCode中的Neovim扩展设置配置文件

.DESCRIPTION
    在Neovim配置目录下创建一个使用dofile加载绝对路径init.lua配置文件的lua文件，
    使得VSCode中的Neovim扩展能够正确加载配置。

.PARAMETER ConfigPath
    Neovim配置目录的路径，默认为当前脚本所在目录

.PARAMETER Force
    强制覆盖已存在的配置文件

.EXAMPLE
    .\setup-neovim-vscode.ps1
    使用默认路径设置Neovim配置

.EXAMPLE
    .\setup-neovim-vscode.ps1 -ConfigPath "C:\Users\username\.config\nvim" -Force
    指定配置路径并强制覆盖已存在的文件

.NOTES
    Author: mudssky
    Date: $(Get-Date -Format 'yyyy-MM-dd')
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = "Neovim配置目录的路径")]
    [string]$ConfigPath = $PSScriptRoot,
    
    [Parameter(HelpMessage = "强制覆盖已存在的配置文件")]
    [switch]$Force
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-NeovimConfigPath {
    <#
    .SYNOPSIS
        获取Neovim配置目录路径
    
    .DESCRIPTION
        根据操作系统返回Neovim的标准配置目录路径
    #>
    
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        # Windows: %LOCALAPPDATA%\nvim
        return Join-Path $env:LOCALAPPDATA "nvim"
    } elseif ($IsMacOS) {
        # macOS: ~/.config/nvim
        return Join-Path $env:HOME ".config/nvim"
    } else {
        # Linux: ~/.config/nvim
        return Join-Path $env:HOME ".config/nvim"
    }
}

function New-NeovimVSCodeConfig {
    <#
    .SYNOPSIS
        创建VSCode Neovim配置文件
    
    .DESCRIPTION
        在Neovim配置目录创建一个使用dofile加载绝对路径init.lua的配置文件，
        并备份现有的init.lua文件，创建新的init.lua文件来加载源配置
    
    .PARAMETER SourceConfigPath
        源配置文件目录路径（包含init.lua的目录）
    
    .PARAMETER Force
        是否强制覆盖已存在的文件
    #>
    param(
        [string]$SourceConfigPath,
        [bool]$Force
    )
    
    try {
        # 获取Neovim标准配置目录
        $neovimConfigPath = Get-NeovimConfigPath
        Write-ColorOutput "Neovim配置目录: $neovimConfigPath" "Cyan"
        
        # 确保Neovim配置目录存在
        if (-not (Test-Path $neovimConfigPath)) {
            Write-ColorOutput "创建Neovim配置目录: $neovimConfigPath" "Yellow"
            New-Item -Path $neovimConfigPath -ItemType Directory -Force | Out-Null
        }
        
        # 获取源init.lua的绝对路径
        $sourceInitLuaPath = Join-Path $SourceConfigPath "init.lua"
        if (-not (Test-Path $sourceInitLuaPath)) {
            Write-Warning "未找到源init.lua文件: $sourceInitLuaPath"
            return @{ Success = $false }
        }
        
        # 转换为Unix风格路径（Lua中使用）
        $luaPath = $sourceInitLuaPath.Replace("\", "/")
        
        # Neovim配置目录中的init.lua路径
        $neovimInitLuaPath = Join-Path $neovimConfigPath "init.lua"
        $backupPath = ""
        
        # 备份现有的init.lua文件（如果存在）
        if (Test-Path $neovimInitLuaPath) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupPath = Join-Path $neovimConfigPath "init.lua.backup_$timestamp"
            
            if (-not $Force) {
                Write-ColorOutput "发现现有的init.lua文件: $neovimInitLuaPath" "Yellow"
                $response = Read-Host "是否继续并备份现有文件? (y/N)"
                if ($response -notmatch '^[Yy]') {
                    Write-ColorOutput "操作已取消" "Red"
                    return @{ Success = $false }
                }
            }
            
            Copy-Item -Path $neovimInitLuaPath -Destination $backupPath -Force
            Write-ColorOutput "✓ 已备份现有init.lua文件到: $backupPath" "Green"
        }
        
        # 获取源配置目录的Lua路径
        $sourceLuaPath = (Join-Path $SourceConfigPath "lua").Replace("\", "/")
        
        # 创建新的init.lua文件内容
        $initLuaContent = @"
-- Neovim 配置文件
-- 自动生成于: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
-- 作者: mudssky
-- 此文件通过dofile加载源配置文件，并支持VSCode环境

-- 源配置文件路径
local source_config_path = "$luaPath"
local source_config_dir = "$($SourceConfigPath.Replace("\", "/"))"
local source_lua_dir = "$sourceLuaPath"

-- 设置 Lua 模块搜索路径
-- 将源配置的 lua 目录添加到 Lua 搜索路径
package.path = source_lua_dir .. "/?.lua;" .. source_lua_dir .. "/?/init.lua;" .. package.path

-- 检查源配置文件是否存在
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- 加载源配置文件
if file_exists(source_config_path) then
    dofile(source_config_path)
else
    -- 输出错误信息
    vim.api.nvim_err_writeln("错误: 无法找到源配置文件: " .. source_config_path)
    vim.api.nvim_err_writeln("请检查路径是否正确，或者源配置文件是否存在")
    vim.api.nvim_err_writeln("当前工作目录: " .. vim.fn.getcwd())
end

-- VSCode 特定配置
if vim.g.vscode then
    -- 在VSCode环境中的特殊配置
    -- 可以在这里添加VSCode特定的键映射和设置
    -- 例如：禁用某些插件或调整键映射
end
"@
        
        # 写入新的init.lua文件
        Set-Content -Path $neovimInitLuaPath -Value $initLuaContent -Encoding UTF8
        Write-ColorOutput "✓ 成功创建新的init.lua文件: $neovimInitLuaPath" "Green"
        
        # 不再创建单独的VSCode配置文件，因为init.lua已经包含了VSCode支持
        Write-ColorOutput "✓ init.lua文件已包含VSCode环境支持" "Green"
        
        # 显示配置信息
        Write-ColorOutput "`n配置信息:" "Cyan"
        Write-ColorOutput "  源配置文件: $sourceInitLuaPath" "White"
        Write-ColorOutput "  新init.lua文件: $neovimInitLuaPath" "White"
        if ($backupPath) {
            Write-ColorOutput "  备份文件: $backupPath" "White"
        }
        Write-ColorOutput "  Lua路径: $luaPath" "White"
        
        return @{
            Success = $true
            InitLuaPath = $neovimInitLuaPath
            BackupPath = $backupPath
        }
    }
    catch {
        Write-Error "创建配置文件时发生错误: $($_.Exception.Message)"
        return @{ Success = $false }
    }
}

function Show-Usage {
    param(
        [string]$InitLuaPath,
        [string]$BackupPath
    )
    
    Write-ColorOutput "`nNeovim 配置设置完成!" "Green"
    Write-ColorOutput "`n配置说明:" "Cyan"
    Write-ColorOutput "1. 新的init.lua文件已创建: $InitLuaPath" "White"
    Write-ColorOutput "   该文件会自动加载源配置并进行路径检查" "White"
    Write-ColorOutput "   同时包含VSCode环境检测和特殊配置支持" "White"
    if ($BackupPath) {
        Write-ColorOutput "2. 原有配置已备份到: $BackupPath" "White"
    }
    Write-ColorOutput "`nVSCode集成说明:" "Cyan"
    Write-ColorOutput "1. 在VSCode中安装 'VSCode Neovim' 扩展" "White"
    Write-ColorOutput "2. VSCode会自动使用Neovim的标准配置文件 ($InitLuaPath)" "White"
    Write-ColorOutput "3. 如需自定义VSCode特定配置，可在init.lua的VSCode部分添加" "White"
    Write-ColorOutput "4. 重启VSCode以使配置生效" "White"
    Write-ColorOutput "`n注意事项:" "Yellow"
    Write-ColorOutput "- 如果源配置文件路径发生变化，请重新运行此脚本" "White"
    Write-ColorOutput "- 新的init.lua会在启动时检查源文件是否存在" "White"
    Write-ColorOutput "- VSCode环境下会自动应用VSCode特定配置" "White"
}

# 主执行逻辑
try {
    Write-ColorOutput "=== VSCode Neovim 配置设置 ===" "Cyan"
    Write-ColorOutput "源配置目录: $ConfigPath" "White"
    
    if ($PSCmdlet.ShouldProcess($ConfigPath, "创建VSCode Neovim配置")) {
        $result = New-NeovimVSCodeConfig -SourceConfigPath $ConfigPath -Force $Force.IsPresent
        
        if ($result.Success) {
            Show-Usage -InitLuaPath $result.InitLuaPath -BackupPath $result.BackupPath
        } else {
            Write-ColorOutput "配置设置失败" "Red"
            exit 1
        }
    }
}
catch {
    Write-Error "脚本执行失败: $($_.Exception.Message)"
    exit 1
}

Write-ColorOutput "`n脚本执行完成" "Green"