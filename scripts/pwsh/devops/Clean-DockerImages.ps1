#!/usr/bin/env pwsh

<#
.SYNOPSIS
    清理冗余 Docker 镜像并释放磁盘空间

.DESCRIPTION
    该脚本提供默认安全、可预览、可配置的 Docker 镜像清理能力。
    默认模式会清理 dangling 镜像与超过时间阈值、且未被运行中容器使用的镜像；
    启用 -Aggressive 后会清理所有未被运行中容器使用且未命中保留规则的镜像。

.PARAMETER DryRun
    预览模式。仅输出候选、预计释放空间和将执行命令，不执行删除。

.PARAMETER Interactive
    启用 `fzf` 多选交互。脚本会将候选镜像送入 `fzf`，仅删除用户选中的条目。
    若未安装 `fzf`，脚本会立即失败并提示安装。

.PARAMETER Aggressive
    激进模式。清理范围扩大到所有未被运行中容器使用且未受保护的镜像。

.PARAMETER UntilHours
    默认保守模式下的镜像年龄阈值（小时）。默认 240 小时。

.PARAMETER KeepRepository
    需要保留的仓库名列表（例如：ubuntu、postgres）。命中则跳过删除。

.PARAMETER KeepTagRegex
    需要保留的 tag 正则表达式。命中则跳过删除。

.PARAMETER IncludeBuildCache
    同时清理 Docker build cache（builder cache）。

.PARAMETER Force
    删除镜像时追加 `docker image rm -f`。

.EXAMPLE
    .\Clean-DockerImages.ps1 -DryRun
    预览默认保守清理候选，不执行删除。

.EXAMPLE
    .\Clean-DockerImages.ps1 -UntilHours 720 -KeepRepository ubuntu,postgres
    清理 720 小时前镜像，保留 ubuntu 与 postgres 仓库镜像。

.EXAMPLE
    .\Clean-DockerImages.ps1 -Aggressive -KeepTagRegex '^(latest|stable)$'
    激进模式清理，保留 latest/stable tag。

.EXAMPLE
    .\Clean-DockerImages.ps1 -Interactive -DryRun -UntilHours 24
    使用 `fzf` 多选候选镜像（预览模式，不执行实际删除）。

.EXAMPLE
    .\Clean-DockerImages.ps1 -Interactive -Aggressive
    进入 `fzf` 多选交互并在激进模式下执行清理。

.NOTES
    依赖 Docker CLI、可用的 Docker daemon 与 `fzf`（仅 Interactive 模式）。
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$DryRun,
    [switch]$Interactive,
    [switch]$Aggressive,

    [ValidateRange(1, 87600)]
    [int]$UntilHours = 240,

    [string[]]$KeepRepository = @(),
    [string]$KeepTagRegex,

    [switch]$IncludeBuildCache,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-ImageId {
    param([string]$ImageId)

    if ([string]::IsNullOrWhiteSpace($ImageId)) { return '' }

    $normalized = $ImageId.Trim().ToLowerInvariant()
    if ($normalized.StartsWith('sha256:')) {
        $normalized = $normalized.Substring(7)
    }

    return $normalized
}

function Convert-HumanSizeToBytes {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0L }

    $value = $Text.Trim().ToUpperInvariant()
    $match = [regex]::Match($value, '([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?B)')
    if (-not $match.Success) { return 0L }

    $number = [double]$match.Groups[1].Value
    $unit = $match.Groups[2].Value
    $power = switch ($unit) {
        'B' { 0 }
        'KB' { 1 }
        'MB' { 2 }
        'GB' { 3 }
        'TB' { 4 }
        'PB' { 5 }
        'EB' { 6 }
        default { 0 }
    }

    return [int64][Math]::Round($number * [Math]::Pow(1024, $power))
}

function Format-Bytes {
    param([long]$Bytes)

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $size = [double]$Bytes
    $index = 0

    while ($size -ge 1024 -and $index -lt ($units.Count - 1)) {
        $size /= 1024
        $index++
    }

    if ($index -eq 0) {
        return ('{0:N0} {1}' -f $size, $units[$index])
    }

    return ('{0:N2} {1}' -f $size, $units[$index])
}

function Get-DockerCommandText {
    param([string[]]$Arguments)
    return 'docker ' + ($Arguments -join ' ')
}

function Invoke-DockerRead {
    param(
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    try {
        $output = @(& docker @Arguments)
        if ($LASTEXITCODE -ne 0) {
            $message = (Get-DockerCommandText -Arguments $Arguments) + " failed with exit code $LASTEXITCODE"
            throw $message
        }

        return $output
    }
    catch {
        if ($AllowFailure) {
            return @()
        }

        throw $_
    }
}

function Invoke-DockerAction {
    param(
        [string[]]$Arguments,
        [string]$Target,
        [string]$Action,
        [switch]$AllowFailure
    )

    $commandText = Get-DockerCommandText -Arguments $Arguments

    if ($DryRun) {
        Write-Output ("[DryRun] " + $commandText)
        return $true
    }

    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
        return $false
    }

    try {
        & docker @Arguments | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $message = (Get-DockerCommandText -Arguments $Arguments) + " failed with exit code $LASTEXITCODE"
            throw $message
        }

        return $true
    }
    catch {
        if ($AllowFailure) {
            Write-Warning ("命令执行失败（已忽略）: " + $commandText)
            Write-Warning $_.Exception.Message
            if ($Action -eq '删除 Docker 镜像' -and -not $Force -and $_.Exception.Message -match 'must be forced|being used by stopped container') {
                Write-Warning '检测到镜像被已停止容器引用。可使用 -Force 重试，或先执行 docker container prune -f 清理停止容器。'
            }
            return $false
        }

        throw $_
    }
}

function Get-FzfInstallHint {
    if ($IsLinux) {
        return '请先安装 fzf，例如：sudo apt-get install -y fzf 或 sudo dnf install -y fzf'
    }

    if ($IsMacOS) {
        return '请先安装 fzf，例如：brew install fzf'
    }

    if ($IsWindows) {
        return '请先安装 fzf，例如：winget install junegunn.fzf 或 choco install fzf'
    }

    return '请先安装 fzf 并确保其在 PATH 中。'
}

function Assert-FzfAvailable {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        throw ("未检测到 fzf。{0}" -f (Get-FzfInstallHint))
    }
}

function Select-CandidatesByFzf {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    if ($Candidates.Count -eq 0) {
        return @()
    }

    $rows = foreach ($candidate in $Candidates) {
        $age = if ($null -eq $candidate.AgeHours) { '-' } else { [string]$candidate.AgeHours }
        $size = Format-Bytes -Bytes ([int64]$candidate.SizeBytes)
        $refs = ($candidate.RepoTags | Select-Object -First 2) -join ', '
        $idShort = $candidate.Id.Substring(0, [Math]::Min(12, $candidate.Id.Length))
        "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $candidate.Id, $idShort, $candidate.Reason, $age, $size, $refs
    }

    $fzfArgs = @(
        '--multi',
        '--layout=reverse',
        '--height=80%',
        '--border',
        '--prompt', 'Select images > ',
        '--header', 'Tab 多选, Enter 确认, Esc 取消',
        '--delimiter', "`t",
        '--with-nth', '2,3,4,5,6'
    )

    $selectedRows = @($rows | & fzf @fzfArgs)
    $fzfExitCode = $LASTEXITCODE

    if ($fzfExitCode -eq 130) {
        Write-Warning '已取消 fzf 选择，本次不删除任何镜像。'
        return @()
    }

    if ($fzfExitCode -ne 0) {
        throw ("fzf 执行失败，exit code: {0}" -f $fzfExitCode)
    }

    if ($selectedRows.Count -eq 0) {
        Write-Warning '未选择任何镜像，本次不删除。'
        return @()
    }

    $selectedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $selectedRows) {
        $parts = $row -split "`t", 2
        if ($parts.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
            $null = $selectedIds.Add((Normalize-ImageId -ImageId $parts[0]))
        }
    }

    return @($Candidates | Where-Object { $selectedIds.Contains($_.Id) })
}

function Assert-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI 不可用，请先安装 Docker 并确保 `docker` 在 PATH 中。'
    }

    try {
        & docker info --format '{{.ServerVersion}}' *> $null
        if ($LASTEXITCODE -ne 0) {
            throw 'Docker daemon 不可用'
        }
    }
    catch {
        throw 'Docker daemon 不可用，请确保 Docker 已启动并可访问。'
    }
}

function Get-DockerDfSnapshot {
    $snapshot = [ordered]@{
        Rows    = @{}
        RawText = ''
    }

    $jsonLines = Invoke-DockerRead -Arguments @('system', 'df', '--format', '{{json .}}') -AllowFailure
    foreach ($line in $jsonLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $row = $line | ConvertFrom-Json
            if ($null -ne $row -and -not [string]::IsNullOrWhiteSpace($row.Type)) {
                $snapshot.Rows[$row.Type] = $row
            }
        }
        catch {
            # 忽略格式异常，回退到 raw text 展示
        }
    }

    $raw = @(Invoke-DockerRead -Arguments @('system', 'df') -AllowFailure)
    if ($raw.Count -gt 0) {
        $snapshot.RawText = ($raw -join [Environment]::NewLine)
    }

    return [PSCustomObject]$snapshot
}

function Get-KeepReason {
    param(
        [PSCustomObject]$Image,
        [System.Collections.Generic.HashSet[string]]$KeepRepoSet,
        [string]$TagRegex
    )

    foreach ($ref in $Image.References) {
        $repo = $ref.Repository
        $tag = $ref.Tag

        if (-not [string]::IsNullOrWhiteSpace($repo) -and $KeepRepoSet.Contains($repo.ToLowerInvariant())) {
            return ("仓库命中保留规则: " + $repo)
        }

        if (-not [string]::IsNullOrWhiteSpace($TagRegex) -and -not [string]::IsNullOrWhiteSpace($tag)) {
            if ($tag -match $TagRegex) {
                return ("Tag 命中保留规则: " + $tag)
            }
        }
    }

    return $null
}

function Get-DockerImages {
    $lines = Invoke-DockerRead -Arguments @('image', 'ls', '--no-trunc', '--format', '{{json .}}')
    $imageMap = @{}

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $item = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        $normalizedId = Normalize-ImageId -ImageId $item.ID
        if ([string]::IsNullOrWhiteSpace($normalizedId)) { continue }

        if (-not $imageMap.ContainsKey($normalizedId)) {
            $imageMap[$normalizedId] = [PSCustomObject]@{
                Id         = $normalizedId
                References = New-Object 'System.Collections.Generic.List[object]'
                IsDangling = $false
                CreatedUtc = $null
                SizeBytes  = 0L
            }
        }

        $repo = [string]$item.Repository
        $tag = [string]$item.Tag
        $imageMap[$normalizedId].References.Add([PSCustomObject]@{
                Repository = $repo
                Tag        = $tag
                RepoTag    = ("${repo}:$tag")
            })

        if ($repo -eq '<none>' -or $tag -eq '<none>') {
            $imageMap[$normalizedId].IsDangling = $true
        }
    }

    foreach ($key in @($imageMap.Keys)) {
        $inspect = @(Invoke-DockerRead -Arguments @('image', 'inspect', ("sha256:" + $key), '--format', '{{json .}}') -AllowFailure)
        if ($inspect.Count -eq 0) { continue }

        try {
            $info = ($inspect[0] | ConvertFrom-Json)
            if ($null -ne $info.Size) {
                $imageMap[$key].SizeBytes = [int64]$info.Size
            }
            if (-not [string]::IsNullOrWhiteSpace($info.Created)) {
                $imageMap[$key].CreatedUtc = [DateTime]::Parse($info.Created).ToUniversalTime()
            }
        }
        catch {
            # 忽略单镜像 inspect 异常
        }
    }

    return @($imageMap.Values)
}

function Get-RunningImageSet {
    $running = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $containerIds = @(
        @(Invoke-DockerRead -Arguments @('ps', '-q', '--no-trunc') -AllowFailure) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($containerId in $containerIds) {
        $imageIds = @(Invoke-DockerRead -Arguments @('inspect', $containerId, '--format', '{{.Image}}') -AllowFailure)
        foreach ($imageId in $imageIds) {
            $id = Normalize-ImageId -ImageId $imageId
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $null = $running.Add($id)
            }
        }
    }

    return $running
}

function Show-ImageSummary {
    param(
        [PSCustomObject]$Snapshot,
        [string]$Label
    )

    $row = $null
    if ($Snapshot.Rows.ContainsKey('Images')) {
        $row = $Snapshot.Rows['Images']
    }

    if ($null -ne $row) {
        Write-Output ("[$Label] Images: Total={0}, Active={1}, Size={2}, Reclaimable={3}" -f $row.TotalCount, $row.Active, $row.Size, $row.Reclaimable)
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Snapshot.RawText)) {
        Write-Output ("[$Label] docker system df 输出:")
        Write-Output $Snapshot.RawText
        return
    }

    Write-Output ("[$Label] 无法获取 docker system df 信息")
}

Assert-DockerAvailable
if ($Interactive) {
    Assert-FzfAvailable
}

if (-not [string]::IsNullOrWhiteSpace($KeepTagRegex)) {
    try {
        $null = [regex]::new($KeepTagRegex)
    }
    catch {
        throw ("KeepTagRegex 不是合法正则表达式: " + $KeepTagRegex)
    }
}

$keepRepoSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($repo in $KeepRepository) {
    if ([string]::IsNullOrWhiteSpace($repo)) { continue }
    $null = $keepRepoSet.Add($repo.Trim().ToLowerInvariant())
}

if ($Aggressive) {
    Write-Warning '已启用 -Aggressive：将尝试清理所有未被运行中容器使用且未受保留规则保护的镜像。'
}

$startedAtUtc = (Get-Date).ToUniversalTime()
$before = Get-DockerDfSnapshot
Show-ImageSummary -Snapshot $before -Label 'Before'

$images = Get-DockerImages
$runningImageSet = Get-RunningImageSet

$candidates = New-Object 'System.Collections.Generic.List[object]'
$keptCount = 0
$runningCount = 0
$ageFilteredCount = 0

foreach ($image in $images) {
    if ($runningImageSet.Contains($image.Id)) {
        $runningCount++
        continue
    }

    $keepReason = Get-KeepReason -Image $image -KeepRepoSet $keepRepoSet -TagRegex $KeepTagRegex
    if (-not [string]::IsNullOrWhiteSpace($keepReason)) {
        $keptCount++
        continue
    }

    $ageHours = $null
    if ($null -ne $image.CreatedUtc) {
        $ageHours = [Math]::Floor(($startedAtUtc - $image.CreatedUtc).TotalHours)
    }

    $reason = $null
    if ($Aggressive) {
        $reason = 'aggressive-unused'
    }
    elseif ($image.IsDangling) {
        $reason = 'dangling'
    }
    elseif ($null -ne $ageHours -and $ageHours -ge $UntilHours) {
        $reason = ("older-than-{0}h" -f $UntilHours)
    }
    else {
        $ageFilteredCount++
    }

    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        $refs = @($image.References | ForEach-Object { $_.RepoTag } | Sort-Object -Unique)
        $candidates.Add([PSCustomObject]@{
                Id        = $image.Id
                Reason    = $reason
                AgeHours  = $ageHours
                SizeBytes = $image.SizeBytes
                RepoTags  = $refs
            })
    }
}

$candidates = @($candidates | Sort-Object -Property @{ Expression = 'SizeBytes'; Descending = $true }, @{ Expression = 'AgeHours'; Descending = $true })

$estimatedBytes = 0L
foreach ($candidate in $candidates) {
    $estimatedBytes += [int64]$candidate.SizeBytes
}

Write-Output ''
Write-Output ("扫描镜像总数: {0}" -f $images.Count)
Write-Output ("运行中容器引用跳过: {0}" -f $runningCount)
Write-Output ("保留规则跳过: {0}" -f $keptCount)
Write-Output ("年龄阈值跳过: {0}" -f $ageFilteredCount)
Write-Output ("可清理候选: {0}" -f $candidates.Count)
Write-Output ("预计可释放: {0}" -f (Format-Bytes -Bytes $estimatedBytes))

if ($candidates.Count -gt 0) {
    Write-Output ''
    Write-Output '候选镜像预览（前 20 条）:'
    $preview = $candidates |
    Select-Object -First 20 |
    Select-Object `
    @{ Name = 'ImageId'; Expression = { $_.Id.Substring(0, [Math]::Min(12, $_.Id.Length)) } }, `
        Reason, `
    @{ Name = 'AgeHours'; Expression = { if ($null -eq $_.AgeHours) { '-' } else { $_.AgeHours } } }, `
    @{ Name = 'Size'; Expression = { Format-Bytes -Bytes $_.SizeBytes } }, `
    @{ Name = 'Refs'; Expression = { ($_.RepoTags | Select-Object -First 2) -join ', ' } }

    $tableText = ($preview | Format-Table -AutoSize | Out-String -Width 220).TrimEnd()
    Write-Output $tableText
}

if ($Interactive -and $candidates.Count -gt 0) {
    Write-Output ''
    Write-Output '进入 fzf 多选交互（仅删除你选中的镜像）...'
    $candidates = @(Select-CandidatesByFzf -Candidates $candidates)

    $selectedBytes = 0L
    foreach ($candidate in $candidates) {
        $selectedBytes += [int64]$candidate.SizeBytes
    }

    Write-Output ("fzf 选中数量: {0}" -f $candidates.Count)
    Write-Output ("fzf 选中预计释放: {0}" -f (Format-Bytes -Bytes $selectedBytes))
}

$removedCount = 0
$failedCount = 0

foreach ($candidate in $candidates) {
    $args = @('image', 'rm')
    if ($Force) {
        $args += '-f'
    }
    $args += ("sha256:" + $candidate.Id)

    $targetLabel = if ($candidate.RepoTags.Count -gt 0) {
        ($candidate.RepoTags | Select-Object -First 3) -join ', '
    }
    else {
        $candidate.Id.Substring(0, [Math]::Min(12, $candidate.Id.Length))
    }

    $ok = Invoke-DockerAction -Arguments $args -Target $targetLabel -Action '删除 Docker 镜像' -AllowFailure
    if ($ok) {
        if (-not $DryRun) {
            $removedCount++
        }
    }
    else {
        if (-not $DryRun) {
            $failedCount++
        }
    }
}

if ($IncludeBuildCache) {
    $builderArgs = @('builder', 'prune', '-f', '--filter', ("until={0}h" -f $UntilHours))
    if ($Aggressive) {
        $builderArgs += '-a'
    }

    $null = Invoke-DockerAction -Arguments $builderArgs -Target 'Docker builder cache' -Action '清理 Docker build cache' -AllowFailure
}

$after = Get-DockerDfSnapshot
Show-ImageSummary -Snapshot $after -Label 'After'

$beforeImageRow = $null
$afterImageRow = $null
if ($before.Rows.ContainsKey('Images')) { $beforeImageRow = $before.Rows['Images'] }
if ($after.Rows.ContainsKey('Images')) { $afterImageRow = $after.Rows['Images'] }

if ($null -ne $beforeImageRow -and $null -ne $afterImageRow) {
    $beforeBytes = Convert-HumanSizeToBytes -Text ([string]$beforeImageRow.Size)
    $afterBytes = Convert-HumanSizeToBytes -Text ([string]$afterImageRow.Size)
    $delta = $beforeBytes - $afterBytes

    Write-Output ''
    Write-Output ("镜像占用变化: {0} -> {1}" -f $beforeImageRow.Size, $afterImageRow.Size)
    if ($delta -ge 0) {
        Write-Output ("估算实际释放: {0}" -f (Format-Bytes -Bytes $delta))
    }
    else {
        Write-Output ("估算占用增加: {0}" -f (Format-Bytes -Bytes ([Math]::Abs($delta))))
    }
}

if (-not $DryRun) {
    Write-Output ''
    Write-Output ("删除完成: success={0}, failed={1}" -f $removedCount, $failedCount)
}
else {
    Write-Output ''
    Write-Output 'DryRun 模式未执行实际删除。'
}
