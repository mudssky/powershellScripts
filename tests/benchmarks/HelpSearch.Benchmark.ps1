<#
.SYNOPSIS
    对比模块帮助搜索的自定义解析与 Get-Help 路径性能。

.DESCRIPTION
    复用 `psutils/modules/help.psm1` 中的帮助搜索能力，输出一份可读的
    性能对比结果；在需要脚本消费时，也支持写出 JSON 报告。

.PARAMETER SearchTerm
    搜索关键词，默认使用 `Get`。

.PARAMETER ModulePath
    要扫描的模块或脚本根目录，默认指向仓库内 `psutils`。

.PARAMETER OutputPath
    可选的 JSON 输出文件路径。

.PARAMETER AsJson
    仅输出 JSON 结果，便于测试或其他脚本消费。

.EXAMPLE
    pnpm benchmark -- help-search

.EXAMPLE
    pnpm benchmark -- help-search -SearchTerm install -OutputPath ./artifacts/help-search.json
#>

[CmdletBinding()]
param(
    [string]$SearchTerm = 'Get',
    [string]$ModulePath,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$helpModulePath = Join-Path $repoRoot 'psutils' 'modules' 'help.psm1'
if (-not (Test-Path $helpModulePath)) {
    throw "帮助搜索模块不存在: $helpModulePath"
}

$effectiveModulePath = if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    Join-Path $repoRoot 'psutils'
}
else {
    $ModulePath
}

if (-not (Test-Path $effectiveModulePath)) {
    throw "待扫描路径不存在: $effectiveModulePath"
}

Import-Module $helpModulePath -Force -ErrorAction Stop

try {
    # benchmark 需要机器可读输出时，通过 Quiet 保持 stdout 干净；
    # 交互式运行则仍沿用模块内的彩色摘要输出。
    $report = if ($AsJson -or -not [string]::IsNullOrWhiteSpace($OutputPath)) {
        Test-HelpSearchPerformance -SearchTerm $SearchTerm -ModulePath $effectiveModulePath -Quiet
    }
    else {
        Test-HelpSearchPerformance -SearchTerm $SearchTerm -ModulePath $effectiveModulePath
    }

    $json = $report | ConvertTo-Json -Depth 5

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $outputDirectory = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }

        Set-Content -Path $OutputPath -Value $json -Encoding utf8NoBOM
    }

    if ($AsJson) {
        $json
        return
    }
}
finally {
    Remove-Module help -Force -ErrorAction SilentlyContinue
}
