#!/usr/bin/env pwsh
<#
.SYNOPSIS
    构建 PostgreSQL Toolkit 的单文件脚本与帮助文档。

.DESCRIPTION
    将 PostgreSQL Toolkit 的多文件源码按固定顺序拼装为单文件 PowerShell 脚本，
    并同步输出独立 Markdown 帮助文档，便于分发与离线查看。

.PARAMETER SourceRoot
    PostgreSQL Toolkit 源码目录，默认为当前 build 目录的上一级。

.PARAMETER OutputScriptPath
    单文件脚本输出路径。

.PARAMETER OutputHelpPath
    独立帮助文档输出路径。
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..'),
    [string]$OutputScriptPath = (Join-Path $PSScriptRoot '..' '..' 'Postgres-Toolkit.ps1'),
    [string]$OutputHelpPath = (Join-Path $PSScriptRoot '..' '..' 'Postgres-Toolkit.Help.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    读取脚本文件并返回原始内容。

.DESCRIPTION
    在拼装前统一校验文件存在性，避免遗漏源码片段导致 bundle 不完整。

.PARAMETER Path
    待读取的脚本文件路径。

.OUTPUTS
    string
    返回脚本文件的原始文本内容。
#>
function Get-BundleFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "缺少源码片段: $Path"
    }

    return Get-Content -Path $Path -Raw
}

<#
.SYNOPSIS
    从 `main.ps1` 提取命令分发函数定义。

.DESCRIPTION
    使用 PowerShell AST 读取 `Invoke-PostgresToolkitCommand` 的源码范围，
    避免直接拼接 `main.ps1` 时把 `param(...)` 块放到非法位置。

.PARAMETER MainScriptPath
    `main.ps1` 的完整路径。

.OUTPUTS
    string
    返回函数定义源码文本。
#>
function Get-MainDispatchFunctionContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MainScriptPath
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($MainScriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $errorText = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "解析 main.ps1 失败: $errorText"
    }

    $functionAst = $ast.Find(
        {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-PostgresToolkitCommand'
        },
        $true
    )

    if ($null -eq $functionAst) {
        throw "未在 main.ps1 中找到 Invoke-PostgresToolkitCommand。"
    }

    return $functionAst.Extent.Text
}

$bundleParts = @(
    'core/logging.ps1'
    'core/process.ps1'
    'core/arguments.ps1'
    'core/connection.ps1'
    'core/context.ps1'
    'core/formats.ps1'
    'core/validation.ps1'
    'platforms/windows.ps1'
    'platforms/macos.ps1'
    'platforms/linux.ps1'
    'commands/help.ps1'
    'commands/backup.ps1'
    'commands/restore.ps1'
    'commands/import-csv.ps1'
    'commands/install-tools.ps1'
)

$mainScriptPath = Join-Path $SourceRoot 'main.ps1'
$bundleContent = New-Object 'System.Collections.Generic.List[string]'

$bundleContent.Add('#!/usr/bin/env pwsh')
$bundleContent.Add('<#')
$bundleContent.Add('.SYNOPSIS')
$bundleContent.Add('    PostgreSQL 常用备份、恢复、CSV 导入与工具安装命令行工具。')
$bundleContent.Add('')
$bundleContent.Add('.DESCRIPTION')
$bundleContent.Add('    单文件分发产物，内嵌 PostgreSQL Toolkit 的核心 helper、命令翻译和帮助输出。')
$bundleContent.Add('')
$bundleContent.Add('.PARAMETER CommandName')
$bundleContent.Add('    要执行的子命令名称，例如 `backup`、`restore`、`import-csv`、`install-tools`。')
$bundleContent.Add('')
$bundleContent.Add('.PARAMETER RawArguments')
$bundleContent.Add('    透传给子命令解析器的剩余参数数组。')
$bundleContent.Add('#>')
$bundleContent.Add('[CmdletBinding(PositionalBinding = $false)]')
$bundleContent.Add('param(')
$bundleContent.Add('    [Parameter(Position = 0)]')
$bundleContent.Add('    [string]$CommandName,')
$bundleContent.Add('')
$bundleContent.Add('    [Parameter(ValueFromRemainingArguments = $true)]')
$bundleContent.Add('    [string[]]$RawArguments')
$bundleContent.Add(')')
$bundleContent.Add('')
$bundleContent.Add('Set-StrictMode -Version Latest')
$bundleContent.Add('$ErrorActionPreference = ''Stop''')

foreach ($relativePath in $bundleParts) {
    $fullPath = Join-Path $SourceRoot $relativePath
    $bundleContent.Add('')
    $bundleContent.Add("# region $relativePath")
    $bundleContent.Add((Get-BundleFileContent -Path $fullPath))
    $bundleContent.Add("# endregion $relativePath")
}

$bundleContent.Add('')
$bundleContent.Add('# region main-dispatch')
$bundleContent.Add((Get-MainDispatchFunctionContent -MainScriptPath $mainScriptPath))
$bundleContent.Add('# endregion main-dispatch')
$bundleContent.Add('')
$bundleContent.Add('if ($env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN -ne ''1'') {')
$bundleContent.Add('    $result = Invoke-PostgresToolkitCommand -CommandName $CommandName -RawArguments $RawArguments')
$bundleContent.Add('    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {')
$bundleContent.Add('        Write-Output $result.Output')
$bundleContent.Add('    }')
$bundleContent.Add('')
$bundleContent.Add('    exit $result.ExitCode')
$bundleContent.Add('}')

$scriptDirectory = Split-Path -Path $OutputScriptPath -Parent
$helpDirectory = Split-Path -Path $OutputHelpPath -Parent
if (-not [string]::IsNullOrWhiteSpace($scriptDirectory)) {
    New-Item -Path $scriptDirectory -ItemType Directory -Force | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($helpDirectory)) {
    New-Item -Path $helpDirectory -ItemType Directory -Force | Out-Null
}

Set-Content -Path $OutputScriptPath -Value ($bundleContent -join [Environment]::NewLine) -Encoding utf8NoBOM
Copy-Item -Path (Join-Path $SourceRoot 'docs/help.md') -Destination $OutputHelpPath -Force
