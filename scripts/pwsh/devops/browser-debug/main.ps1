#!/usr/bin/env pwsh
<##
.SYNOPSIS
    管理 Windows Chromium 独立 CDP 调试 Profile 与 SSH 转发配置。
.DESCRIPTION
    提供传统 CLI 命令树、稳定 JSON 输出、PowerShell Native Completion 和安全的进程所有权判断。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'schema.ps1')
. (Join-Path $PSScriptRoot 'registry.ps1')
. (Join-Path $PSScriptRoot 'runtime.ps1')
. (Join-Path $PSScriptRoot 'commands.ps1')
. (Join-Path $PSScriptRoot 'completion.ps1')

<##
.SYNOPSIS
    将命令结果渲染为人类文本或稳定 JSON。
.PARAMETER Data
    命令结果。
.PARAMETER AsJson
    是否输出 JSON。
.OUTPUTS
    System.String
    返回可写入标准输出的文本。
#>
function Format-BrowserDebugOutput {
    [CmdletBinding()]
    param([object]$Data, [switch]$AsJson)
    if ($AsJson) { return [pscustomobject]@{ schemaVersion = 1; success = $true; data = $Data } | ConvertTo-Json -Depth 30 }
    if ($Data -is [string]) { return $Data }
    if ($null -eq $Data) { return '' }
    return ($Data | Format-List * | Out-String).TrimEnd()
}

<##
.SYNOPSIS
    执行 browser-debug 原始参数命令。
.PARAMETER Arguments
    原始 CLI 参数。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回退出码和输出文本。
#>
function Invoke-BrowserDebugCli {
    [CmdletBinding()]
    param([string[]]$Arguments)
    try {
        $tokens = @($Arguments)
        if ($tokens.Count -eq 0) { return [pscustomobject]@{ ExitCode = 0; Output = Get-BrowserDebugHelpText } }
        if ($tokens[0] -eq '--help') {
            if ($tokens.Count -ne 1) { throw "多余位置参数: $($tokens[1..($tokens.Count - 1)] -join ' ')" }
            return [pscustomobject]@{ ExitCode = 0; Output = Get-BrowserDebugHelpText }
        }
        if ($tokens[0] -eq 'help') {
            if ($tokens.Count -gt 3) { throw "多余位置参数: $($tokens[3..($tokens.Count - 1)] -join ' ')" }
            $helpResource = if ($tokens.Count -gt 1) { $tokens[1] } else { $null }
            $helpAction = if ($tokens.Count -gt 2) { $tokens[2] } else { $null }
            return [pscustomobject]@{ ExitCode = 0; Output = Get-BrowserDebugHelpText -Resource $helpResource -Action $helpAction }
        }
        if ($tokens[0] -eq 'completion') {
            if ($tokens.Count -ne 2 -or $tokens[1] -ne 'powershell') { throw '用法: browser-debug completion powershell' }
            $entryPath = Join-Path (Get-BrowserDebugRepoRoot) 'bin/browser-debug.ps1'
            return [pscustomobject]@{ ExitCode = 0; Output = ". '$((Join-Path $PSScriptRoot 'completion.ps1').Replace("'", "''"))'; Register-BrowserDebugCompletion -CommandPath '$($entryPath.Replace("'", "''"))'" }
        }
        if ($tokens[0] -eq '__complete') {
            $parsedCompletion = ConvertFrom-BrowserDebugArguments -Arguments $tokens[1..($tokens.Count - 1)]
            $line = [string]$parsedCompletion.Options['line']
            $position = [int]$parsedCompletion.Options['position']
            $values = Get-BrowserDebugCompletionCandidates -Line $line -Position $position -RegistryPath ([string]$parsedCompletion.Options['registry-path'])
            return [pscustomobject]@{ ExitCode = 0; Output = ($values -join [Environment]::NewLine) }
        }
        $parsed = ConvertFrom-BrowserDebugArguments -Arguments $tokens
        if ($parsed.Help) { return [pscustomobject]@{ ExitCode = 0; Output = Get-BrowserDebugHelpText -Resource $parsed.Resource -Action $parsed.Action } }
        if ($parsed.Action -notin 'list', 'get' -and [string]::IsNullOrWhiteSpace($parsed.Name)) { throw "缺少名称参数: $($parsed.Resource) $($parsed.Action) <name>" }
        if ($env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN -ne '1') { Assert-BrowserDebugWindowsPlatform }
        if ($parsed.Resource -eq 'profile' -and $parsed.Action -eq 'start' -and [string]$parsed.Options['mode'] -eq 'lan') {
            Write-Warning 'LAN CDP 无认证，可完全控制浏览器。请只在受控网络中显式使用，并自行配置防火墙。'
        }
        $data = Invoke-BrowserDebugParsedCommand -Parsed $parsed
        return [pscustomobject]@{ ExitCode = 0; Output = Format-BrowserDebugOutput -Data $data -AsJson:$parsed.AsJson }
    }
    catch {
        $asJson = @($Arguments) -contains '--json'
        $message = $_.Exception.Message
        $output = if ($asJson) { [pscustomobject]@{ schemaVersion = 1; success = $false; error = [pscustomobject]@{ code = 'BrowserDebugError'; message = $message } } | ConvertTo-Json -Depth 10 } else { "错误: $message" }
        return [pscustomobject]@{ ExitCode = 1; Output = $output }
    }
}

if ($env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN -ne '1') {
    $result = Invoke-BrowserDebugCli -Arguments $args
    if (-not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
        if ($result.ExitCode -eq 0) { Write-Output $result.Output } else { [Console]::Error.WriteLine($result.Output) }
    }
    exit $result.ExitCode
}
