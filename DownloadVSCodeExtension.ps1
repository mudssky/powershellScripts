<#
.SYNOPSIS
    下载指定的VS Code扩展包(.vsix文件)。

.DESCRIPTION
    此脚本用于从Visual Studio Marketplace下载特定版本的VS Code扩展包。
    通过提供发布者、扩展名称和版本号，脚本将自动下载对应的.vsix文件。
    插件市场 ： https://marketplace.visualstudio.com/
.PARAMETER Publisher
    扩展发布者的名称。

.PARAMETER ExtensionName
    扩展的名称。

.PARAMETER Version
    扩展的版本号。

.PARAMETER OutputPath
    可选参数，指定下载文件的保存位置。默认保存在用户的Downloads文件夹。

.EXAMPLE
    .\DownloadVSCodeExtension.ps1 -Publisher "ms-python" -ExtensionName "python" -Version "2023.4.0"
    从Visual Studio Marketplace下载Python扩展2023.4.0版本。

.NOTES
    需要网络连接才能下载扩展包。
    如果指定的输出路径不存在，脚本会自动创建该目录。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Publisher,
    
    [Parameter(Mandatory = $true)]
    [string]$ExtensionName,
    
    [Parameter(Mandatory = $true)]
    [string]$Version,
    
    [string]$OutputPath = "$env:USERPROFILE\Downloads"
)

# 构造下载URL
$downloadUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$Publisher/vsextensions/$ExtensionName/$Version/vspackage"

# 确保输出目录存在
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

# 设置下载文件名
$fileName = "$Publisher-$ExtensionName-$Version.vsix"
$outputFile = Join-Path -Path $OutputPath -ChildPath $fileName

try {
    Write-Host "正在下载 $Publisher.$ExtensionName 版本 $Version..."
    
    # 使用Invoke-WebRequest下载文件
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    
    if (Test-Path -Path $outputFile) {
        Write-Host "下载完成! 文件已保存到: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "下载失败，请检查URL和参数是否正确" -ForegroundColor Red
    }
}
catch {
    Write-Host "下载过程中出错: $_" -ForegroundColor Red
}