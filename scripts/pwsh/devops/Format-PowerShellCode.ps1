<#
.SYNOPSIS
    使用 `pwshfmt-rs` 格式化 PowerShell 代码文件

.DESCRIPTION
    本脚本是 PowerShell 入口适配层，内部调用 Rust CLI `pwshfmt-rs`。
    保留原有参数习惯（Path/Recurse/GitChanged/ShowOnly/Strict），
    以兼容现有 npm/pnpm 工作流。

.PARAMETER Path
    要格式化的文件或目录路径。支持多个路径，可以通过位置参数传递。

.PARAMETER Recurse
    递归处理子目录中的 PowerShell 文件。

.PARAMETER Settings
    兼容参数（已弃用）。
    `pwshfmt-rs` 不使用 PSScriptAnalyzer settings，此参数会被忽略。

.PARAMETER ShowOnly
    显示将要格式化的文件列表，但不实际执行格式化操作。

.PARAMETER GitChanged
    仅格式化 Git 工作区中有改动的 PowerShell 文件（含已暂存与未暂存）。

.PARAMETER Strict
    启用 strict fallback（映射为 `pwshfmt-rs --strict-fallback`）。

.EXAMPLE
    .\Format-PowerShellCode.ps1 -GitChanged

.EXAMPLE
    .\Format-PowerShellCode.ps1 -Path . -Recurse

.EXAMPLE
    .\Format-PowerShellCode.ps1 -GitChanged -Strict
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true, HelpMessage = "要格式化的文件或目录路径（支持多个文件）")]
    [string[]]$Path,

    [Parameter(HelpMessage = "递归处理子目录")]
    [switch]$Recurse,

    [Parameter(HelpMessage = "兼容参数（已弃用）：PSScriptAnalyzer settings 文件路径")]
    [string]$Settings,

    [Parameter(HelpMessage = "显示将要格式化的文件，但不实际执行")]
    [switch]$ShowOnly,

    [Parameter(HelpMessage = "仅格式化 Git 改动文件")]
    [switch]$GitChanged,

    [Parameter(HelpMessage = "启用 strict fallback")]
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:SupportedExtensions = @('.ps1', '.psm1', '.psd1')

function Get-EffectiveInputPaths {
    [CmdletBinding()]
    param()

    return @(
        @($Path) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Test-IsPowerShellFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $extension = [System.IO.Path]::GetExtension($FilePath)
    return $extension -in $script:SupportedExtensions
}

function Get-RepositoryRoot {
    [CmdletBinding()]
    param()

    $root = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')
    return $root.Path
}

function Get-PowerShellFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [bool]$UseRecurse
    )

    $files = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -Path $InputPath -PathType Leaf) {
        $item = Get-Item -LiteralPath $InputPath
        if (Test-IsPowerShellFile -FilePath $item.FullName) {
            $null = $files.Add($item.FullName)
        }
        else {
            Write-Warning "文件 $InputPath 不是支持的 PowerShell 文件类型"
        }

        return @($files)
    }

    if (Test-Path -Path $InputPath -PathType Container) {
        if ($UseRecurse) {
            $items = Get-ChildItem -LiteralPath $InputPath -Recurse -File
        }
        else {
            $items = Get-ChildItem -LiteralPath $InputPath -File
        }

        foreach ($item in $items) {
            if (Test-IsPowerShellFile -FilePath $item.FullName) {
                $null = $files.Add($item.FullName)
            }
        }

        return @($files)
    }

    $wildcardItems = if ($UseRecurse) {
        Get-ChildItem -Path $InputPath -Recurse -File -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -Path $InputPath -File -ErrorAction SilentlyContinue
    }

    foreach ($item in @($wildcardItems)) {
        if (Test-IsPowerShellFile -FilePath $item.FullName) {
            $null = $files.Add($item.FullName)
        }
    }

    if ($files.Count -eq 0) {
        Write-Warning "指定路径不存在或未匹配到 PowerShell 文件: $InputPath"
    }

    return @($files)
}

function Get-GitChangedPowerShellFiles {
    [CmdletBinding()]
    param()

    try {
        $gitRoot = (git rev-parse --show-toplevel 2>$null)
    }
    catch {
        Write-Error '无法检测到 Git 仓库根目录，请确认当前目录在 Git 仓库内'
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
        Write-Error '无法检测到 Git 仓库根目录，请确认当前目录在 Git 仓库内'
        return @()
    }

    $pathSpec = @('*.ps1', '*.psm1', '*.psd1')

    $changed = @()
    $changed += git -C $gitRoot diff '--name-only' '--diff-filter=ACMRT' '--' @pathSpec
    $changed += git -C $gitRoot diff '--name-only' '--diff-filter=ACMRT' '--cached' '--' @pathSpec

    $changed = @($changed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($changed.Count -eq 0) {
        return @()
    }

    $fullPaths = foreach ($rel in $changed) {
        $candidate = Join-Path $gitRoot $rel
        if (Test-Path -Path $candidate -PathType Leaf) {
            $candidate
        }
    }

    return @($fullPaths)
}

function Resolve-TargetFiles {
    [CmdletBinding()]
    param()

    $inputPaths = @(Get-EffectiveInputPaths)

    if (-not $GitChanged -and $inputPaths.Count -eq 0) {
        throw '请至少指定 `-GitChanged` 或 `-Path`。'
    }

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($GitChanged) {
        foreach ($file in @(Get-GitChangedPowerShellFiles)) {
            $null = $set.Add($file)
        }
    }

    foreach ($inputPath in $inputPaths) {
        foreach ($file in @(Get-PowerShellFiles -InputPath $inputPath -UseRecurse:$Recurse.IsPresent)) {
            $null = $set.Add($file)
        }
    }

    return @($set | Sort-Object)
}

function Build-PwshFmtRsArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $args = @('run', '--manifest-path', $ManifestPath, '--', 'write')

    if ($GitChanged) {
        $args += '--git-changed'
    }

    foreach ($inputPath in @(Get-EffectiveInputPaths)) {
        $args += @('--path', $inputPath)
    }

    if ($Recurse.IsPresent) {
        $args += '--recurse'
    }

    if ($Strict.IsPresent) {
        $args += '--strict-fallback'
    }

    return ,$args
}

function Invoke-PwshFmtRs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    if (-not (Get-Command -Name cargo -ErrorAction SilentlyContinue)) {
        throw '未找到 cargo，请先安装 Rust toolchain。'
    }

    $manifestPath = Join-Path $RepoRoot 'projects/clis/pwshfmt-rs/Cargo.toml'
    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        throw "未找到 pwshfmt-rs 清单文件: $manifestPath"
    }

    $cargoArgs = Build-PwshFmtRsArguments -ManifestPath $manifestPath
    Write-Host "调用 pwshfmt-rs: cargo $($cargoArgs -join ' ')" -ForegroundColor DarkCyan

    & cargo @cargoArgs
}

function Main {
    if (-not [string]::IsNullOrWhiteSpace($Settings)) {
        Write-Warning '参数 -Settings 已弃用：pwshfmt-rs 不使用 PSScriptAnalyzer settings，将忽略该参数。'
    }

    $files = @(Resolve-TargetFiles)

    if ($files.Count -eq 0) {
        if ($GitChanged) {
            Write-Host '未找到 Git 改动的 PowerShell 文件，已快速退出' -ForegroundColor DarkYellow
        }
        else {
            Write-Warning '在指定路径中未找到 PowerShell 文件'
        }
        return
    }

    Write-Host "找到 $($files.Count) 个 PowerShell 文件" -ForegroundColor Cyan

    if ($ShowOnly) {
        Write-Host '将要格式化的文件:' -ForegroundColor Yellow
        foreach ($file in $files) {
            Write-Host "  - $file" -ForegroundColor Gray
        }
        return
    }

    $repoRoot = Get-RepositoryRoot

    if ($PSCmdlet.ShouldProcess($repoRoot, '执行 pwshfmt-rs write')) {
        Invoke-PwshFmtRs -RepoRoot $repoRoot
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Error "pwshfmt-rs 执行失败，退出码: $exitCode"
            exit $exitCode
        }
    }

    Write-Host "`n格式化完成!" -ForegroundColor Green
    Write-Host "成功: $($files.Count) 个文件" -ForegroundColor Green
}

try {
    Main
}
catch {
    Write-Error $_
    exit 1
}
