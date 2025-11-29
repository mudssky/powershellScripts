<#
.SYNOPSIS
加载并覆盖当前配置文件，执行前打印现有配置用于确认。

.DESCRIPTION
按 `-Mode` 从源配置复制到当前配置目标路径。默认源为 `$PSScriptRoot/codex/config.toml` 或
`$PSScriptRoot/claude/config.toml`。默认目标依据模式自动映射到用户主目录：
`codex` → `$HOME/.codex/config.toml`，`claude` → `$HOME/.claude/config.toml`。
执行前会打印当前配置内容（若存在）。当目标文件存在时会要求确认（可用 `-Force` 跳过），
支持 `-WhatIf`/`-Confirm`。复制完成后进行 `SHA256` 哈希校验以确保覆盖成功。

.PARAMETER Mode
配置源模式，支持 `codex`、`claude`（若对应目录不存在则报错）。默认 `codex`。

.PARAMETER DestinationPath
当前配置的目标路径。未提供时将根据 `Mode` 自动映射到用户主目录下的默认位置。

.PARAMETER Force
跳过目标文件存在时的确认提示，直接执行覆盖。

.EXAMPLE
# 覆盖当前配置为 codex 的配置（默认目标：$HOME/.codex/config.toml）
./loadConfig.ps1 -Mode codex -Confirm:$false

.EXAMPLE
# 仅预览将要执行的变更（不实际复制）
./loadConfig.ps1 -Mode codex -WhatIf

.EXAMPLE
# 自定义目标路径，并在目标存在时跳过确认
./loadConfig.ps1 -Mode codex -DestinationPath 'D:/configs/codex.toml' -Force -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('codex', 'claude')]
    [string]$Mode = 'codex',

    [Parameter()] [string]$DestinationPath,

    [Parameter()] [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ConfigSourcePath {
    param(
        [Parameter(Mandatory)][ValidateSet('codex', 'claude')] [string]$Mode
    )

    switch ($Mode) {
        'codex' { return (Join-Path -Path $PSScriptRoot -ChildPath 'codex/config.toml') }
        'claude' { return (Join-Path -Path $PSScriptRoot -ChildPath 'claude/config.toml') }
        default { throw "不支持的模式: $Mode" }
    }
}

function Get-DefaultDestinationPath {
    param(
        [Parameter(Mandatory)][ValidateSet('codex', 'claude')] [string]$Mode
    )

    $homePath = [System.Environment]::GetFolderPath('UserProfile')
    switch ($Mode) {
        'codex' { return (Join-Path -Path $homePath -ChildPath (Join-Path '.codex'  'config.toml')) }
        'claude' { return (Join-Path -Path $homePath -ChildPath (Join-Path '.claude' 'config.toml')) }
        default { throw "不支持的模式: $Mode" }
    }
}

function Show-CurrentConfig {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Output "当前配置路径: $Path"
        Write-Output "当前配置内容如下:" 
        Write-Output (Get-Content -LiteralPath $Path -Raw)
    }
    else {
        Write-Output "当前配置路径: $Path"
        Write-Output "当前配置不存在，将创建并覆盖。"
    }
}

function Copy-ConfigWithVerify {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "源配置不存在: $Source"
    }

    $destDir = Split-Path -Path $Destination -Parent
    if (-not [string]::IsNullOrWhiteSpace($destDir) -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir | Out-Null
    }

    $needConfirm = (Test-Path -LiteralPath $Destination) -and (-not $Force)

    if ($needConfirm) {
        $title = "确认覆盖当前配置？"
        $query = "目标文件已存在:\n$Destination\n将用源配置覆盖:\n$Source\n是否继续？"
        if (-not $PSCmdlet.ShouldContinue($query, $title)) {
            return [PSCustomObject]@{
                Mode        = $Mode
                SourcePath  = $Source
                Destination = $Destination
                Status      = 'Skipped'
                Reason      = 'UserDeclinedOverwrite'
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("$Destination", "用源配置覆盖当前配置")) {
        $bytes = [System.IO.File]::ReadAllBytes($Source)
        [System.IO.File]::WriteAllBytes($Destination, $bytes)

        $srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
        $destHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash

        if ($srcHash -ne $destHash) {
            throw "覆盖后校验失败：源/目标哈希不一致"
        }

        [PSCustomObject]@{
            Mode          = $Mode
            SourcePath    = $Source
            Destination   = $Destination
            HashAlgorithm = 'SHA256'
            Hash          = $destHash
            Status        = 'OK'
        }
    }
}

# 主流程
$sourcePath = Get-ConfigSourcePath -Mode $Mode
if (-not $PSBoundParameters.ContainsKey('DestinationPath') -or [string]::IsNullOrWhiteSpace($DestinationPath)) {
    $DestinationPath = Get-DefaultDestinationPath -Mode $Mode
}
Show-CurrentConfig -Path $DestinationPath
$result = Copy-ConfigWithVerify -Source $sourcePath -Destination $DestinationPath
if ($result) { Write-Output $result }
