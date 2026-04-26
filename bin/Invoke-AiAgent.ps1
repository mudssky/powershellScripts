#!/usr/bin/env -S pwsh -NoProfile

# Auto-generated shim by Manage-BinScripts.ps1
# Source: /Users/mudssky/projects/powershellScripts/scripts/pwsh/ai/agent-runner/main.ps1

<#
.SYNOPSIS
    通过本机 coding agent 执行 prompt 或内置 preset。

.DESCRIPTION
    支持 `codex`、`claude`、`opencode` 三个 agent，并通过 Markdown preset 管理常用任务。

.PARAMETER CommandName
    顶层命令，支持 `run`、`commit`、`help`。

.PARAMETER Prompt
    直接执行的 prompt 文本。

.PARAMETER PromptFile
    prompt 文件路径。

.PARAMETER Preset
    prompt preset 名称。
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$CommandName,

    [Parameter(Position = 1)]
    [string]$Prompt,

    [string]$PromptFile,
    [string]$Preset,

    [ValidateSet('codex', 'claude', 'opencode')]
    [string]$Agent,

    [string]$Model,

    [ValidateSet('minimal', 'low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort,

    [string]$WorkDir,
    [switch]$Json,
    [switch]$DryRun,
    [string[]]$ExtraArgs
)

$SourcePath = Join-Path $PSScriptRoot '../scripts/pwsh/ai/agent-runner/main.ps1'
if (-not (Test-Path $SourcePath)) {
    Write-Error "Cannot find source script at $SourcePath"
    exit 1
}
& $SourcePath @PSBoundParameters
exit $LASTEXITCODE
