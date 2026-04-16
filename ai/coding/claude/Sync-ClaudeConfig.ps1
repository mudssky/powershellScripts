#!/usr/bin/env pwsh

<#
.SYNOPSIS
    生成并同步 Claude Code 的共享配置到用户目录。

.DESCRIPTION
    此脚本把仓库内的共享模板 `config/settings.json` 与可选本机覆盖
    `config/settings.local.json` 合并为最终的 `~/.claude/settings.json`，
    同时把 `.claude` 下受管的共享资产同步到真实用户目录。

    当检测到旧的 `~/.claude -> repo/.claude` 软链接模式时，脚本会先创建备份，
    再将其迁移为真实目录，避免后续运行态数据继续写回仓库。

.PARAMETER SourceRoot
    Claude 配置源目录。默认使用当前脚本所在目录。

.PARAMETER GlobalClaudePath
    用户实际使用的 Claude 配置目录。默认是 `Join-Path $HOME '.claude'`。

.PARAMETER BackupRoot
    迁移旧软链接或目录前存放备份的根目录。默认是 `Join-Path $HOME '.claude-sync-backups'`。

.OUTPUTS
    PSCustomObject
    返回本次同步的摘要信息，包括目标目录、设置文件路径、是否读取了 local 覆盖、
    是否执行了软链接迁移以及受管文件数量。
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$SourceRoot = $PSScriptRoot,

    [Parameter()]
    [string]$GlobalClaudePath = (Join-Path $HOME '.claude'),

    [Parameter()]
    [string]$BackupRoot = (Join-Path $HOME '.claude-sync-backups')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SyncCmdlet = $PSCmdlet
$script:ManagedRelativePatterns = @(
    'CLAUDE.md'
    'config.json'
    'commands/*.md'
    'output-styles/*.md'
    'ccline/config.toml'
    'ccline/models.toml'
    'ccline/themes/*.toml'
    'skills/**/*.md'
)
$script:LocalOnlyEnvKeys = @(
    'ANTHROPIC_API_KEY'
    'ANTHROPIC_BASE_URL'
    'OPENAI_API_KEY'
    'OPENAI_BASE_URL'
)
$script:ManagedManifestFileName = '.sync-manifest.json'

function Test-IsDictionaryValue {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    return $Value -is [System.Collections.IDictionary]
}

function Test-IsListValue {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    return (
        $null -ne $Value -and
        $Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [System.Collections.IDictionary])
    )
}

function Resolve-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Path
    )

    return [System.IO.Path]::GetRelativePath($BasePath, $Path).Replace('\', '/')
}

function Join-PathFragments {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $result = $BasePath
    foreach ($segment in ($RelativePath -split '[\\/]')) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            $result = Join-Path $result $segment
        }
    }

    return $result
}

function Get-StableCollectionKey {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return '<null>'
    }

    if ((Test-IsDictionaryValue -Value $Value) -or (Test-IsListValue -Value $Value)) {
        return ($Value | ConvertTo-Json -Depth 100 -Compress)
    }

    return [string]$Value
}

function Read-JsonFileAsHashtable {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Label
    )

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 100
    }
    catch {
        throw "解析 ${Label} 失败：$($_.Exception.Message)"
    }
}

function Merge-ClaudeConfigValue {
    param(
        [Parameter()]
        [AllowNull()]
        $BaseValue,

        [Parameter()]
        [AllowNull()]
        $OverrideValue
    )

    if ($null -eq $OverrideValue) {
        return $null
    }

    if ((Test-IsDictionaryValue -Value $BaseValue) -and (Test-IsDictionaryValue -Value $OverrideValue)) {
        $merged = [ordered]@{}

        foreach ($key in $BaseValue.Keys) {
            $merged[$key] = $BaseValue[$key]
        }

        foreach ($key in $OverrideValue.Keys) {
            if ($merged.Contains($key)) {
                $merged[$key] = Merge-ClaudeConfigValue -BaseValue $merged[$key] -OverrideValue $OverrideValue[$key]
            }
            else {
                $merged[$key] = $OverrideValue[$key]
            }
        }

        return $merged
    }

    if ((Test-IsListValue -Value $BaseValue) -and (Test-IsListValue -Value $OverrideValue)) {
        $items = New-Object System.Collections.ArrayList
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        foreach ($item in @($BaseValue) + @($OverrideValue)) {
            $stableKey = Get-StableCollectionKey -Value $item
            if ($seen.Add($stableKey)) {
                [void]$items.Add($item)
            }
        }

        return @($items.ToArray())
    }

    return $OverrideValue
}

function Assert-SharedTemplateSafety {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value,

        [Parameter()]
        [string]$CurrentPath = ''
    )

    if (Test-IsDictionaryValue -Value $Value) {
        foreach ($key in $Value.Keys) {
            $nextPath = if ([string]::IsNullOrWhiteSpace($CurrentPath)) { [string]$key } else { "$CurrentPath.$key" }
            $normalizedKey = ([string]$key).ToUpperInvariant()

            # 这些 env 键属于本机覆盖层，不允许重新回到共享模板里。
            if ($CurrentPath -eq 'env' -and $script:LocalOnlyEnvKeys -contains $normalizedKey) {
                throw "共享模板不能包含本机专属 env 键：$nextPath。请把它移动到 config/settings.local.json。"
            }

            # 共享模板里不应出现明显的 secrets 命名，避免再次把敏感值带回可提交文件。
            if ($normalizedKey -match '(API[_-]?KEY|TOKEN|SECRET|PASSWORD)') {
                throw "共享模板检测到疑似敏感键：$nextPath。请改为放入 config/settings.local.json。"
            }

            Assert-SharedTemplateSafety -Value $Value[$key] -CurrentPath $nextPath
        }

        return
    }

    if (Test-IsListValue -Value $Value) {
        for ($index = 0; $index -lt @($Value).Count; $index++) {
            Assert-SharedTemplateSafety -Value @($Value)[$index] -CurrentPath "$CurrentPath[$index]"
        }

        return
    }

    if ($Value -is [string] -and $Value -match '(^sk-[A-Za-z0-9_-]+)|(^Bearer\s+\S+)') {
        throw "共享模板在 $CurrentPath 中检测到疑似密钥值。请把敏感值移动到 config/settings.local.json。"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    foreach ($item in Get-ChildItem -LiteralPath $SourcePath -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $DestinationPath $item.Name) -Recurse -Force
    }
}

function New-BackupSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$BackupRootPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $BackupRootPath "claude-config-$timestamp"

    if ($script:SyncCmdlet.ShouldProcess($BackupRootPath, "Create backup snapshot $backupPath")) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Copy-DirectoryContents -SourcePath $SourcePath -DestinationPath $backupPath
    }

    return $backupPath
}

function Get-LinkTargetText {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    if ($Item.Target -is [System.Array]) {
        return (@($Item.Target) -join ', ')
    }

    return [string]$Item.Target
}

function Ensure-RealClaudeDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [string]$BackupRootPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($script:SyncCmdlet.ShouldProcess($TargetPath, 'Create Claude configuration directory')) {
            New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        }

        return [pscustomobject]@{
            MigratedFromLink = $false
            BackupPath       = $null
            LinkTarget       = $null
        }
    }

    $item = Get-Item -LiteralPath $TargetPath -Force
    if (-not $item.PSIsContainer) {
        throw "目标路径不是目录：$TargetPath"
    }

    $isLink = $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)
    if (-not $isLink) {
        return [pscustomobject]@{
            MigratedFromLink = $false
            BackupPath       = $null
            LinkTarget       = $null
        }
    }

    $backupPath = New-BackupSnapshot -SourcePath $TargetPath -BackupRootPath $BackupRootPath
    $linkTarget = Get-LinkTargetText -Item $item

    if ($script:SyncCmdlet.ShouldProcess($TargetPath, 'Replace symbolic link with a real Claude directory')) {
        Remove-Item -LiteralPath $TargetPath -Force
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

        if ($backupPath) {
            Copy-DirectoryContents -SourcePath $backupPath -DestinationPath $TargetPath
        }
    }

    return [pscustomobject]@{
        MigratedFromLink = $true
        BackupPath       = $backupPath
        LinkTarget       = $linkTarget
    }
}

function Write-JsonFileAtomically {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    $directoryPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directoryPath)) {
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
    }

    $tempFilePath = Join-Path $directoryPath ("settings.{0}.tmp" -f [System.Guid]::NewGuid().ToString('N'))
    $json = $Value | ConvertTo-Json -Depth 100

    if ($script:SyncCmdlet.ShouldProcess($Path, 'Write generated Claude settings')) {
        Set-Content -LiteralPath $tempFilePath -Value $json -Encoding utf8NoBOM
        Move-Item -LiteralPath $tempFilePath -Destination $Path -Force
    }
}

function Get-ManagedSourceRelativeFiles {
    param(
        [Parameter(Mandatory)]
        [string]$ManagedSourceRoot
    )

    $relativeFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($item in Get-ChildItem -LiteralPath $ManagedSourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $relativePath = Resolve-RelativePath -BasePath $ManagedSourceRoot -Path $item.FullName
        foreach ($pattern in $script:ManagedRelativePatterns) {
            if ($relativePath -like $pattern) {
                [void]$relativeFiles.Add($relativePath)
                break
            }
        }
    }

    return @($relativeFiles | Sort-Object)
}

function Read-ManagedManifest {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return @()
    }

    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 20
        return @($manifest.managedFiles | ForEach-Object { [string]$_ })
    }
    catch {
        Write-Warning "读取旧的 managed manifest 失败，将跳过 prune：$($_.Exception.Message)"
        return @()
    }
}

function Write-ManagedManifest {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string[]]$ManagedFiles
    )

    $manifest = [ordered]@{
        managedFiles = @($ManagedFiles | Sort-Object)
    }

    Write-JsonFileAtomically -Path $ManifestPath -Value $manifest
}

function Remove-EmptyManagedParents {
    param(
        [Parameter(Mandatory)]
        [string]$ChildPath,

        [Parameter(Mandatory)]
        [string]$StopPath
    )

    $currentPath = Split-Path -Parent $ChildPath
    $fullStopPath = [System.IO.Path]::GetFullPath($StopPath)

    while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        $fullCurrentPath = [System.IO.Path]::GetFullPath($currentPath)
        if ($fullCurrentPath -eq $fullStopPath) {
            break
        }

        if (-not (Test-Path -LiteralPath $currentPath)) {
            $currentPath = Split-Path -Parent $currentPath
            continue
        }

        if ((Get-ChildItem -LiteralPath $currentPath -Force).Count -gt 0) {
            break
        }

        if ($script:SyncCmdlet.ShouldProcess($currentPath, 'Remove empty managed directory')) {
            Remove-Item -LiteralPath $currentPath -Force
        }

        $currentPath = Split-Path -Parent $currentPath
    }
}

function Sync-ManagedFiles {
    param(
        [Parameter(Mandatory)]
        [string]$ManagedSourceRoot,

        [Parameter(Mandatory)]
        [string]$ManagedTargetRoot
    )

    $currentManagedFiles = Get-ManagedSourceRelativeFiles -ManagedSourceRoot $ManagedSourceRoot
    $manifestPath = Join-Path $ManagedTargetRoot $script:ManagedManifestFileName
    $previousManagedFiles = Read-ManagedManifest -ManifestPath $manifestPath

    foreach ($relativePath in ($previousManagedFiles | Where-Object { $_ -notin $currentManagedFiles })) {
        $targetPath = Join-PathFragments -BasePath $ManagedTargetRoot -RelativePath $relativePath
        if (Test-Path -LiteralPath $targetPath) {
            if ($script:SyncCmdlet.ShouldProcess($targetPath, 'Remove stale managed Claude asset')) {
                Remove-Item -LiteralPath $targetPath -Recurse -Force
            }

            Remove-EmptyManagedParents -ChildPath $targetPath -StopPath $ManagedTargetRoot
        }
    }

    foreach ($relativePath in $currentManagedFiles) {
        $sourcePath = Join-PathFragments -BasePath $ManagedSourceRoot -RelativePath $relativePath
        $targetPath = Join-PathFragments -BasePath $ManagedTargetRoot -RelativePath $relativePath
        $targetDirectory = Split-Path -Parent $targetPath

        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }

        if ($script:SyncCmdlet.ShouldProcess($targetPath, 'Copy managed Claude asset')) {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }
    }

    Write-ManagedManifest -ManifestPath $manifestPath -ManagedFiles $currentManagedFiles
    return @($currentManagedFiles)
}

$sharedSettingsPath = Join-Path $SourceRoot 'config/settings.json'
$localSettingsPath = Join-Path $SourceRoot 'config/settings.local.json'
$managedSourceRoot = Join-Path $SourceRoot '.claude'
$generatedSettingsPath = Join-Path $GlobalClaudePath 'settings.json'

Write-Host '--- Claude Code 配置同步任务 ---' -ForegroundColor Cyan
Write-Host "[1/4] 读取共享模板: $sharedSettingsPath" -ForegroundColor Gray

if (-not (Test-Path -LiteralPath $sharedSettingsPath)) {
    throw "找不到共享模板：$sharedSettingsPath"
}

$sharedSettings = Read-JsonFileAsHashtable -Path $sharedSettingsPath -Label '共享模板 settings.json'
Assert-SharedTemplateSafety -Value $sharedSettings

$hasLocalSettings = Test-Path -LiteralPath $localSettingsPath
$localSettings = $null
if ($hasLocalSettings) {
    Write-Host "[2/4] 读取本机覆盖: $localSettingsPath" -ForegroundColor Gray
    $localSettings = Read-JsonFileAsHashtable -Path $localSettingsPath -Label '本机覆盖 settings.local.json'
}
else {
    Write-Host "[2/4] 未找到本机覆盖，使用共享模板生成 settings。" -ForegroundColor Gray
}

Write-Host "[3/4] 准备目标目录: $GlobalClaudePath" -ForegroundColor Gray
$directoryState = Ensure-RealClaudeDirectory -TargetPath $GlobalClaudePath -BackupRootPath $BackupRoot

$mergedSettings = if ($localSettings) {
    Merge-ClaudeConfigValue -BaseValue $sharedSettings -OverrideValue $localSettings
}
else {
    $sharedSettings
}

Write-Host "[4/4] 生成 settings 并同步共享资产。" -ForegroundColor Gray
Write-JsonFileAtomically -Path $generatedSettingsPath -Value $mergedSettings
$managedFiles = Sync-ManagedFiles -ManagedSourceRoot $managedSourceRoot -ManagedTargetRoot $GlobalClaudePath

$result = [pscustomobject]@{
    GlobalClaudePath = $GlobalClaudePath
    SettingsPath     = $generatedSettingsPath
    HasLocalSettings = $hasLocalSettings
    MigratedFromLink = $directoryState.MigratedFromLink
    BackupPath       = $directoryState.BackupPath
    LinkTarget       = $directoryState.LinkTarget
    ManagedFileCount = @($managedFiles).Count
}

Write-Host '操作成功！Claude Code 现在使用仓库模板和本机覆盖生成最终配置。' -ForegroundColor Green
$result
