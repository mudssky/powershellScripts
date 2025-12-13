#!/usr/bin/env pwsh

<#
.SYNOPSIS
    下载指定的VS Code扩展包(.vsix文件)。

.DESCRIPTION
    此脚本用于从Visual Studio Marketplace下载特定版本的VS Code扩展包。
    通过提供发布者、扩展名称和版本号，或者使用Identifier参数，脚本将自动下载对应的.vsix文件。
    插件市场 ： https://marketplace.visualstudio.com/

.PARAMETER Publisher
    扩展发布者的名称。必须与ExtensionName一起使用，或使用Identifier替代。

.PARAMETER ExtensionName
    扩展的名称。必须与Publisher一起使用，或使用Identifier替代。

.PARAMETER Identifier
    扩展的完整标识符，格式为"Publisher.ExtensionName"。可替代Publisher和ExtensionName参数。

.PARAMETER Version
    扩展的版本号。

.PARAMETER OutputPath
    可选参数，指定下载文件的保存位置。默认保存在当前目录。

.EXAMPLE
    .\DownloadVSCodeExtension.ps1 -Identifier "ms-python.python" -Version "2023.4.0"
    使用Identifier参数下载Python扩展2023.4.0版本。

.EXAMPLE
    .\DownloadVSCodeExtension.ps1 -Publisher "ms-python" -ExtensionName "python" -Version "2023.4.0"
    分别指定Publisher和ExtensionName下载Python扩展2023.4.0版本。

.NOTES
    需要网络连接才能下载扩展包。
    如果指定的输出路径不存在，脚本会自动创建该目录。
    必须提供Identifier参数或同时提供Publisher和ExtensionName参数。
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Publisher,
    
    [Parameter(Mandatory = $false)]
    [string]$ExtensionName,
    
    [Parameter(Mandatory = $false)]
    [string]$Identifier,
    
    [Parameter(Mandatory = $true)]
    [string]$Version,
    
    [string]$OutputPath = "."
)

# 启用严格模式与错误停止
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 检查参数组合是否有效
if (-not $Identifier -and (-not $Publisher -or -not $ExtensionName)) {
    throw "必须提供 Identifier 参数或同时提供 Publisher 和 ExtensionName 参数"
}

# 如果提供了Identifier，则从中提取Publisher和ExtensionName
if ($Identifier) {
    $parts = $Identifier -split '\.'
    if ($parts.Count -ne 2) {
        throw "Identifier 格式不正确，应为 'Publisher.ExtensionName'"
    }
    $Publisher = $parts[0]
    $ExtensionName = $parts[1]
}

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
    if ($PSCmdlet.ShouldProcess($outputFile, '下载 VS Code 扩展')) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    }
    if (Test-Path -Path $outputFile) {
        Write-Host "下载完成! 文件已保存到: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "下载失败，请检查URL和参数是否正确" -ForegroundColor Red
    }
}
catch {
    Write-Error ("下载过程中出错: " + $_)
    exit 1
}
