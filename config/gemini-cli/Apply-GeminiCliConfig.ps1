<#
.SYNOPSIS
    应用 Gemini CLI 配置文件。
.DESCRIPTION
    此脚本将位于 `config/gemini-cli/settings.json` 的 Gemini CLI 配置文件复制到用户主目录下的 `.gemini/settings.json`。
    它支持 Windows、Linux 和 macOS 操作系统。
.EXAMPLE
    .Apply-GeminiCliConfig.ps1
    将配置文件复制到用户主目录。
.NOTES
    确保在运行此脚本之前，`config/gemini-cli/settings.json` 文件存在。
#>
function Apply-GeminiCliConfig {
    [CmdletBinding()]
    param()

    # 定义源文件路径

    $sourceFilePath = "$PSScriptRoot/settings.json"

    # 确定用户主目录
    $homeDirectory = ""
    if ($IsWindows) {
        $homeDirectory = $env:USERPROFILE
    }
    elseif ($IsLinux -or $IsMacOS) {
        $homeDirectory = $env:HOME
    }
    else {
        Write-Error "不支持的操作系统。"
        return
    }

    # 构建目标目录和文件路径
    $destinationDirectory = Join-Path -Path $homeDirectory -ChildPath ".gemini"
    $destinationFilePath = Join-Path -Path $destinationDirectory -ChildPath "settings.json"

    Write-Host "源文件路径: $sourceFilePath"
    Write-Host "目标目录: $destinationDirectory"
    Write-Host "目标文件路径: $destinationFilePath"

    # 检查源文件是否存在
    if (-not (Test-Path $sourceFilePath)) {
        Write-Error "源文件不存在: $sourceFilePath"
        return
    }

    # 检查并创建目标目录
    if (-not (Test-Path $destinationDirectory)) {
        Write-Host "创建目标目录: $destinationDirectory"
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
    }

    # 复制文件
    try {
        Copy-Item -Path $sourceFilePath -Destination $destinationFilePath -Force -ErrorAction Stop
        Write-Host "配置文件已成功复制到: $destinationFilePath" -ForegroundColor Green
    }
    catch {
        Write-Error "复制文件时发生错误: $($_.Exception.Message)"
    }
}

# 调用函数
Apply-GeminiCliConfig