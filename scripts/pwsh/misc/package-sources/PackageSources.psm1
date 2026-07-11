Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PackageSourceDependenciesLoaded = $false
$script:PackageSourceRoot = $PSScriptRoot

function Import-PackageSourceDependencies {
    <#
    .SYNOPSIS
        加载 package source 引擎依赖的共享模块。

    .DESCRIPTION
        复用 psutils 的配置解析器读取 catalog，避免在独立脚本中维护第二套 JSON 解析逻辑。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    if ($script:PackageSourceDependenciesLoaded) {
        return
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:PackageSourceRoot '../../../..'))
    foreach ($modulePath in @(
            (Join-Path $repoRoot 'psutils/modules/config.psm1')
            (Join-Path $repoRoot 'psutils/modules/json.psm1')
            (Join-Path $script:PackageSourceRoot 'adapters/AdapterSupport.psm1')
            (Join-Path $script:PackageSourceRoot 'adapters/ManagedEnvAdapter.psm1')
            (Join-Path $script:PackageSourceRoot 'adapters/ChsrcCommandAdapter.psm1')
            (Join-Path $script:PackageSourceRoot 'adapters/DockerAdapter.psm1')
            (Join-Path $script:PackageSourceRoot 'adapters/ChsrcSystemAdapter.psm1')
        )) {
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "未找到 package source 依赖模块: $modulePath"
        }
        Import-Module $modulePath -Force
    }
    $script:PackageSourceDependenciesLoaded = $true
}

function Resolve-PackageSourceStateRoot {
    <#
    .SYNOPSIS
        解析 package source 事务状态根目录。

    .OUTPUTS
        string。当前平台的状态根目录。
    #>
    [CmdletBinding()]
    param()

    $overridePath = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_PACKAGE_SOURCE_STATE_ROOT', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
        return [System.IO.Path]::GetFullPath($overridePath)
    }

    if ($IsWindows) {
        $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            throw '无法解析 LOCALAPPDATA，不能创建 package source 状态目录'
        }
        return Join-Path $localAppData 'powershellScripts/package-sources'
    }

    $xdgStateHome = [Environment]::GetEnvironmentVariable('XDG_STATE_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($xdgStateHome)) {
        $homePath = [Environment]::GetEnvironmentVariable('HOME', 'Process')
        $xdgStateHome = Join-Path $homePath '.local/state'
    }
    return Join-Path $xdgStateHome 'powershellScripts/package-sources'
}

function New-PackageSourceTransactionId {
    <#
    .SYNOPSIS
        生成可读且避免冲突的事务 ID。

    .OUTPUTS
        string。UTC 时间戳与随机后缀组成的事务 ID。
    #>
    [CmdletBinding()]
    param()

    return '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [guid]::NewGuid().ToString('N').Substring(0, 8)
}

function Assert-PackageSourceTransactionId {
    <#
    .SYNOPSIS
        校验事务 ID 可安全用作目录名。

    .PARAMETER TransactionId
        待校验事务 ID。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TransactionId
    )

    if ($TransactionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "事务 ID 非法: $TransactionId"
    }
}

function New-PackageSourceException {
    <#
    .SYNOPSIS
        创建带稳定退出码和错误代码的 package source 异常。

    .PARAMETER Message
        面向用户的错误消息。

    .PARAMETER ExitCode
        CLI 退出码。

    .PARAMETER Code
        结构化错误代码。

    .OUTPUTS
        System.InvalidOperationException。Data 中包含 ExitCode 与 Code。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$Code
    )

    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $ExitCode
    $exception.Data['Code'] = $Code
    return $exception
}

function Enter-PackageSourceStateLock {
    <#
    .SYNOPSIS
        获取状态根目录的独占写锁。

    .PARAMETER StateRoot
        状态根目录。

    .OUTPUTS
        System.IO.FileStream。调用方必须在 finally 中 Dispose。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot
    )

    if (-not (Test-Path -LiteralPath $StateRoot)) {
        New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    }
    Set-PackageSourceFileMode -Path $StateRoot -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute)

    $lockPath = Join-Path $StateRoot '.lock'
    try {
        $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        Set-PackageSourceFileMode -Path $lockPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        return $stream
    }
    catch {
        throw (New-PackageSourceException -Message "package source 状态正被另一个进程修改: $StateRoot" -ExitCode 10 -Code 'Blocked')
    }
}

function New-PackageSourceTransaction {
    <#
    .SYNOPSIS
        创建新的 package source 事务及 manifest。

    .PARAMETER StateRoot
        状态根目录。

    .PARAMETER TransactionId
        事务 ID。

    .PARAMETER Mode
        China 或 Auto。

    .OUTPUTS
        hashtable。包含 Paths 与 Manifest。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot,

        [Parameter(Mandatory)]
        [string]$TransactionId,

        [Parameter(Mandatory)]
        [ValidateSet('China', 'Auto')]
        [string]$Mode
    )

    Assert-PackageSourceTransactionId -TransactionId $TransactionId
    $transactionRoot = Join-Path $StateRoot $TransactionId
    $manifestPath = Join-Path $transactionRoot 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        throw "package source 事务已存在: $TransactionId"
    }

    $snapshotRoot = Join-Path $transactionRoot 'snapshots'
    $logRoot = Join-Path $transactionRoot 'logs'
    foreach ($path in @($transactionRoot, $snapshotRoot, $logRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Set-PackageSourceFileMode -Path $path -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute)
    }

    $now = [DateTime]::UtcNow.ToString('o')
    $ownerProcess = Get-Process -Id $PID
    $manifest = [ordered]@{
        SchemaVersion = 1
        TransactionId = $TransactionId
        Mode          = $Mode
        Persistent    = $Mode -eq 'China'
        CreatedAt     = $now
        UpdatedAt     = $now
        Status        = 'Applying'
        OwnerPid      = $PID
        OwnerProcessStartUtc = $ownerProcess.StartTime.ToUniversalTime().ToString('o')
        Resources     = @()
        Targets       = @()
    }
    $null = Write-JsonFileAtomic -Path $manifestPath -Value $manifest -TempPrefix 'manifest'
    Set-PackageSourceFileMode -Path $manifestPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)

    return @{
        Root         = $transactionRoot
        SnapshotRoot = $snapshotRoot
        ManifestPath = $manifestPath
        Manifest     = $manifest
    }
}

function Add-PackageSourceFileSnapshot {
    <#
    .SYNOPSIS
        在事务首次修改文件前保存 snapshot 与 hash。

    .PARAMETER Transaction
        New-PackageSourceTransaction 返回的事务对象。

    .PARAMETER Target
        正在修改该资源的 target。

    .PARAMETER Path
        要保护的文件路径。

    .OUTPUTS
        hashtable。manifest 中的资源记录。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Path
    )

    foreach ($existing in @($Transaction.Manifest.Resources)) {
        if ([string]::Equals([string]$existing.Path, $Path, [System.StringComparison]::Ordinal)) {
            $existing.Targets = @($existing.Targets) + @($Target) | Select-Object -Unique
            return $existing
        }
    }

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $snapshotName = '{0}-{1}.snapshot' -f $Target, [guid]::NewGuid().ToString('N')
    $snapshotPath = Join-Path $Transaction.SnapshotRoot $snapshotName
    if ($exists) {
        Copy-Item -LiteralPath $Path -Destination $snapshotPath
        Set-PackageSourceFileMode -Path $snapshotPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    }

    $resource = [ordered]@{
        Type         = 'File'
        Path         = $Path
        Existed      = $exists
        SnapshotFile = if ($exists) { $snapshotName } else { '' }
        BeforeHash   = Get-PackageSourceFileHash -Path $Path
        AfterHash    = ''
        UnixMode     = if ($exists -and -not $IsWindows) { [int][System.IO.File]::GetUnixFileMode($Path) } else { 0 }
        Targets      = @($Target)
    }
    $Transaction.Manifest.Resources = @($Transaction.Manifest.Resources) + @($resource)
    return $resource
}

function Write-PackageSourceTransactionManifest {
    <#
    .SYNOPSIS
        原子保存事务 manifest。

    .PARAMETER Transaction
        当前事务对象。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction
    )

    $Transaction.Manifest.UpdatedAt = [DateTime]::UtcNow.ToString('o')
    $null = Write-JsonFileAtomic -Path $Transaction.ManifestPath -Value $Transaction.Manifest -TempPrefix 'manifest'
    Set-PackageSourceFileMode -Path $Transaction.ManifestPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
}

function Open-PackageSourceTransaction {
    <#
    .SYNOPSIS
        读取已有 package source 事务。

    .PARAMETER StateRoot
        状态根目录。

    .PARAMETER TransactionId
        要读取的事务 ID。

    .OUTPUTS
        hashtable。包含事务路径和 manifest。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot,

        [Parameter(Mandatory)]
        [string]$TransactionId
    )

    Assert-PackageSourceTransactionId -TransactionId $TransactionId
    $transactionRoot = Join-Path $StateRoot $TransactionId
    $manifestPath = Join-Path $transactionRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "package source 事务不存在: $TransactionId"
    }

    return @{
        Root         = $transactionRoot
        SnapshotRoot = (Join-Path $transactionRoot 'snapshots')
        ManifestPath = $manifestPath
        Manifest     = Read-JsonHashtableFile -Path $manifestPath -Label "package source transaction $TransactionId"
    }
}

function Restore-PackageSourceFileResource {
    <#
    .SYNOPSIS
        恢复事务拥有的单个文件资源。

    .DESCRIPTION
        默认仅在当前 hash 等于事务 after hash 时恢复；Force 会先备份 drift 后的当前文件。

    .PARAMETER Transaction
        当前事务对象。

    .PARAMETER Resource
        manifest 中的文件资源记录。

    .PARAMETER Force
        是否允许在 drift 后人工强制恢复。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction,

        [Parameter(Mandatory)]
        [hashtable]$Resource,

        [switch]$Force
    )

    $path = [string]$Resource.Path
    $currentHash = Get-PackageSourceFileHash -Path $path
    if (-not [string]::IsNullOrWhiteSpace([string]$Resource.AfterHash) -and $currentHash -ne [string]$Resource.AfterHash) {
        if (-not $Force.IsPresent) {
            throw (New-PackageSourceException -Message "检测到 source 配置 drift，拒绝覆盖: $path" -ExitCode 10 -Code 'Blocked')
        }

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $driftBackupPath = '{0}.{1}.drift.bak' -f $path, (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
            Copy-Item -LiteralPath $path -Destination $driftBackupPath
        }
    }

    if ([bool]$Resource.Existed) {
        $snapshotPath = Join-Path $Transaction.SnapshotRoot ([string]$Resource.SnapshotFile)
        if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
            throw "事务 snapshot 不存在: $snapshotPath"
        }

        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $tempPath = Join-Path $directory ('.package-source-restore.{0}.tmp' -f [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $snapshotPath -Destination $tempPath
            Move-Item -LiteralPath $tempPath -Destination $path -Force
        }
        finally {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (-not $IsWindows -and [int]$Resource.UnixMode -ne 0) {
            Set-PackageSourceFileMode -Path $path -Mode ([System.IO.UnixFileMode][int]$Resource.UnixMode)
        }
    }
    else {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    $restoredHash = Get-PackageSourceFileHash -Path $path
    if ($restoredHash -ne [string]$Resource.BeforeHash) {
        throw "source 配置恢复后 hash 不一致: $path"
    }
    $Resource.Status = 'Restored'
    $Resource.RestoredAt = [DateTime]::UtcNow.ToString('o')
}

function Restore-PackageSourceTransaction {
    <#
    .SYNOPSIS
        恢复指定 package source 事务。

    .PARAMETER Transaction
        Open-PackageSourceTransaction 返回的事务对象。

    .PARAMETER Force
        是否允许人工覆盖 drift。

    .OUTPUTS
        object[]。逐 target 的恢复结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction,

        [switch]$Force
    )

    if ([string]$Transaction.Manifest.Status -eq 'Restored') {
        return @($Transaction.Manifest.Targets | ForEach-Object {
                $target = ConvertTo-ConfigHashtable -InputObject $_
                New-PackageSourceResult -Target ([string]$target.Target) -Mode ([string]$Transaction.Manifest.Mode) -Phase 'Runtime' -Adapter ([string]$target.Adapter) -Status 'Restored' -Message '事务已恢复，无需重复写入' -Source ([string]$target.Source) -TransactionId ([string]$Transaction.Manifest.TransactionId)
            })
    }

    $resources = @($Transaction.Manifest.Resources)
    [array]::Reverse($resources)
    foreach ($resourceValue in $resources) {
        $resource = ConvertTo-ConfigHashtable -InputObject $resourceValue
        Restore-PackageSourceFileResource -Transaction $Transaction -Resource $resource -Force:$Force
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($targetValue in @($Transaction.Manifest.Targets)) {
        $target = ConvertTo-ConfigHashtable -InputObject $targetValue
        $target.Status = 'Restored'
        $target.RestoredAt = [DateTime]::UtcNow.ToString('o')
        $results.Add((New-PackageSourceResult -Target ([string]$target.Target) -Mode ([string]$Transaction.Manifest.Mode) -Phase 'Runtime' -Adapter ([string]$target.Adapter) -Status 'Restored' -Message '已恢复事务应用前的 source 配置' -Source ([string]$target.Source) -TransactionId ([string]$Transaction.Manifest.TransactionId)))
    }

    $Transaction.Manifest.Resources = $resources
    $Transaction.Manifest.Targets = @($Transaction.Manifest.Targets | ForEach-Object {
            $target = ConvertTo-ConfigHashtable -InputObject $_
            $target.Status = 'Restored'
            $target.RestoredAt = [DateTime]::UtcNow.ToString('o')
            $target
        })
    $Transaction.Manifest.Status = 'Restored'
    Write-PackageSourceTransactionManifest -Transaction $Transaction
    return $results.ToArray()
}

function Get-PackageSourceTransactionStatusResult {
    <#
    .SYNOPSIS
        读取事务当前状态并检测资源 drift。

    .PARAMETER Transaction
        Open-PackageSourceTransaction 返回的事务对象。

    .OUTPUTS
        object[]。逐 target 的只读状态结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Transaction
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($targetValue in @($Transaction.Manifest.Targets)) {
        $target = ConvertTo-ConfigHashtable -InputObject $targetValue
        $status = [string]$Transaction.Manifest.Status
        if ($status -in @('Active', 'Applying')) {
            $targetResources = @($Transaction.Manifest.Resources | Where-Object { @($_.Targets) -contains [string]$target.Target })
            foreach ($resourceValue in $targetResources) {
                $resource = ConvertTo-ConfigHashtable -InputObject $resourceValue
                if ((Get-PackageSourceFileHash -Path ([string]$resource.Path)) -ne [string]$resource.AfterHash) {
                    $status = 'Drifted'
                    break
                }
            }
            if (
                $status -in @('Active', 'Applying') -and
                [string]$Transaction.Manifest.Mode -eq 'Auto' -and
                -not (Test-PackageSourceTransactionOwnerAlive -Manifest $Transaction.Manifest)
            ) {
                $status = 'Orphaned'
            }
        }

        $rollback = if ($status -in @('Active', 'Applying', 'Drifted', 'Failed')) {
            "./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $($Transaction.Manifest.TransactionId)"
        }
        else {
            ''
        }
        $results.Add((New-PackageSourceResult -Target ([string]$target.Target) -Mode ([string]$Transaction.Manifest.Mode) -Phase 'Runtime' -Adapter ([string]$target.Adapter) -Status $status -Message '只读事务状态' -Source ([string]$target.Source) -Persistent:([bool]$Transaction.Manifest.Persistent) -TransactionId ([string]$Transaction.Manifest.TransactionId) -Rollback $rollback))
    }

    return $results.ToArray()
}

function Test-PackageSourceTransactionOwnerAlive {
    <#
    .SYNOPSIS
        验证 Auto 事务 owner 进程仍是创建事务的同一进程。

    .PARAMETER Manifest
        package source transaction manifest。

    .OUTPUTS
        bool。PID 与启动时间均匹配时为 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Manifest
    )

    if (-not $Manifest.Contains('OwnerPid') -or -not $Manifest.Contains('OwnerProcessStartUtc')) {
        return $false
    }

    try {
        $process = Get-Process -Id ([int]$Manifest.OwnerPid) -ErrorAction Stop
        $expectedStart = [DateTime]::Parse(
            [string]$Manifest.OwnerProcessStartUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        return [Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 1
    }
    catch {
        return $false
    }
}

function Restore-OrphanedAutoTransaction {
    <#
    .SYNOPSIS
        恢复状态目录中 owner 已退出的 Auto 事务。

    .PARAMETER StateRoot
        package source 状态根目录。

    .PARAMETER ExcludeTransactionId
        当前调用明确继续使用的事务 ID，不参与 orphan 扫描。

    .OUTPUTS
        string[]。已恢复的事务 ID。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot,

        [string]$ExcludeTransactionId = ''
    )

    $restoredIds = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $StateRoot -PathType Container)) {
        return $restoredIds.ToArray()
    }

    foreach ($directory in Get-ChildItem -LiteralPath $StateRoot -Directory) {
        if ([string]::Equals($directory.Name, $ExcludeTransactionId, [System.StringComparison]::Ordinal)) {
            continue
        }

        $manifestPath = Join-Path $directory.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }
        $transaction = Open-PackageSourceTransaction -StateRoot $StateRoot -TransactionId $directory.Name
        if (
            [string]$transaction.Manifest.Mode -ne 'Auto' -or
            [string]$transaction.Manifest.Status -notin @('Active', 'Applying') -or
            (Test-PackageSourceTransactionOwnerAlive -Manifest $transaction.Manifest)
        ) {
            continue
        }

        $null = Restore-PackageSourceTransaction -Transaction $transaction
        $restoredIds.Add($directory.Name)
    }

    return $restoredIds.ToArray()
}

function Get-PackageSourceCatalog {
    <#
    .SYNOPSIS
        读取并校验 package source catalog。

    .PARAMETER Path
        可选 catalog 路径；未提供时使用仓库默认配置。

    .OUTPUTS
        hashtable。包含 schema、默认值和 target 定义。
    #>
    [CmdletBinding()]
    param(
        [string]$Path = ''
    )

    Import-PackageSourceDependencies
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:PackageSourceRoot '../../../..'))
    $catalogPath = if ([string]::IsNullOrWhiteSpace($Path)) {
        Join-Path $repoRoot 'config/network/package-sources.json'
    }
    else {
        $Path
    }

    $resolved = Resolve-ConfigSources -Sources @(
        @{
            Type = 'JsonFile'
            Name = 'PackageSources'
            Path = $catalogPath
        }
    ) -BasePath $repoRoot -ErrorOnMissing
    $catalog = $resolved.Values

    if ([int]$catalog.schema_version -ne 1) {
        throw "不支持的 package source catalog schema: $($catalog.schema_version)"
    }
    $catalog.targets = ConvertTo-ConfigHashtable -InputObject $catalog.targets
    if ($catalog.targets.Count -eq 0) {
        throw 'package source catalog 缺少 targets 对象'
    }

    return $catalog
}

function New-PackageSourceResult {
    <#
    .SYNOPSIS
        创建统一的 target 执行结果。

    .PARAMETER Target
        target 名称。

    .PARAMETER Mode
        网络模式。

    .PARAMETER Phase
        当前执行阶段。

    .PARAMETER Adapter
        负责该 target 的 adapter。

    .PARAMETER Status
        target 状态。

    .PARAMETER Message
        面向用户的结果说明。

    .PARAMETER Source
        当前或计划使用的 source；未知时为空。

    .PARAMETER Persistent
        该结果是否对应持久事务。

    .PARAMETER TransactionId
        关联事务 ID。

    .PARAMETER Rollback
        可执行的回滚提示。

    .OUTPUTS
        PSCustomObject。稳定的 target 结果结构。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Mode,

        [Parameter(Mandatory)]
        [string]$Phase,

        [Parameter(Mandatory)]
        [string]$Adapter,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Source = '',

        [bool]$Persistent = $false,

        [string]$TransactionId = '',

        [string]$Rollback = ''
    )

    return [PSCustomObject][ordered]@{
        Target        = $Target
        Mode          = $Mode
        Phase         = $Phase
        Adapter       = $Adapter
        Status        = $Status
        Source        = $Source
        Persistent    = $Persistent
        TransactionId = $TransactionId
        Message       = $Message
        Rollback      = $Rollback
    }
}

function Test-PackageSourceOfficialEndpoint {
    <#
    .SYNOPSIS
        对 target 的官方端点执行有界健康探测。

    .DESCRIPTION
        先发 HEAD，请求不被端点支持时再尝试 GET；任一受控端点在任一次探测成功即返回健康。

    .PARAMETER TargetConfig
        catalog 中的 target 配置。

    .PARAMETER TimeoutSeconds
        单次请求超时秒数。

    .PARAMETER Attempts
        最多探测轮数。

    .OUTPUTS
        PSCustomObject。包含 Healthy、Source 与 Reason。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 5,

        [ValidateRange(1, 5)]
        [int]$Attempts = 2
    )

    $probeUrls = @($TargetConfig.official_probe_urls | ForEach-Object { [string]$_ })
    if ($probeUrls.Count -eq 0) {
        return [PSCustomObject]@{
            Healthy = $false
            Source  = ''
            Reason  = 'catalog 未配置官方探测端点'
        }
    }

    $lastError = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        foreach ($url in $probeUrls) {
            try {
                $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec $TimeoutSeconds -ErrorAction Stop
                if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) {
                    return [PSCustomObject]@{
                        Healthy = $true
                        Source  = $url
                        Reason  = "官方端点第 $attempt 次探测成功"
                    }
                }
            }
            catch {
                $lastError = $_.Exception.Message
                try {
                    $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
                    if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) {
                        return [PSCustomObject]@{
                            Healthy = $true
                            Source  = $url
                            Reason  = "官方端点第 $attempt 次 GET 探测成功"
                        }
                    }
                }
                catch {
                    $lastError = $_.Exception.Message
                }
            }
        }
    }

    return [PSCustomObject]@{
        Healthy = $false
        Source  = $probeUrls[0]
        Reason  = if ([string]::IsNullOrWhiteSpace($lastError)) { '官方端点连续探测失败' } else { "官方端点连续探测失败: $lastError" }
    }
}

function Get-PackageSourceAdapterResourcePath {
    <#
    .SYNOPSIS
        返回 adapter 在当前 target 上拥有的文件资源。

    .PARAMETER Target
        target 名称。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .OUTPUTS
        string[]。Apply 前必须 snapshot 的文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    switch ([string]$TargetConfig.adapter) {
        'managed-env' {
            return @(Get-ManagedEnvPackageSourcePath)
        }
        'chsrc' {
            return @(Get-ChsrcCommandPackageSourceResourcePath -Target $Target)
        }
        'docker' {
            return @(Get-DockerPackageSourcePath)
        }
        'chsrc-system' {
            return @(Get-ChsrcSystemPackageSourceResourcePath -TargetConfig $TargetConfig)
        }
        default {
            throw "package source adapter 尚未实现: $($TargetConfig.adapter)"
        }
    }
}

function Invoke-PackageSourceAdapterApply {
    <#
    .SYNOPSIS
        调用 target 对应的 source adapter。

    .PARAMETER Target
        target 名称。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .PARAMETER MinimumChsrcVersion
        允许的最低 chsrc 版本。

    .PARAMETER Selection
        Auto、First 或指定 provider。

    .PARAMETER MirrorUrl
        Docker adapter 的可选候选镜像覆盖。

    .PARAMETER TimeoutSeconds
        Docker 镜像探活超时秒数。

    .PARAMETER Retry
        Docker 镜像探活重试次数。

    .OUTPUTS
        PSCustomObject。包含 Source、Changed、ChsrcVersion 与 Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [Parameter(Mandatory)]
        [version]$MinimumChsrcVersion,

        [string]$Selection = 'Auto',

        [string[]]$MirrorUrl = @(),

        [int]$TimeoutSeconds = 5,

        [int]$Retry = 1
    )

    $result = switch ([string]$TargetConfig.adapter) {
        'managed-env' {
            Invoke-ManagedEnvPackageSourceApply -Target $Target -TargetConfig $TargetConfig -MinimumChsrcVersion $MinimumChsrcVersion -Selection $Selection
        }
        'chsrc' {
            Invoke-ChsrcCommandPackageSourceApply -Target $Target -TargetConfig $TargetConfig -MinimumChsrcVersion $MinimumChsrcVersion -Selection $Selection
        }
        'docker' {
            $dockerMirrorUrls = if ($MirrorUrl.Count -gt 0) {
                @($MirrorUrl)
            }
            else {
                @($TargetConfig.mirror_urls | ForEach-Object { [string]$_ })
            }
            Invoke-DockerPackageSourceApply -MirrorUrl $dockerMirrorUrls -TimeoutSeconds $TimeoutSeconds -Retry $Retry
        }
        'chsrc-system' {
            Invoke-ChsrcSystemPackageSourceApply -Target $Target -TargetConfig $TargetConfig -MinimumChsrcVersion $MinimumChsrcVersion -Selection $Selection
        }
        default {
            throw "package source adapter 尚未实现: $($TargetConfig.adapter)"
        }
    }
    $message = switch ([string]$TargetConfig.adapter) {
        'managed-env' { 'source 已写入受管环境文件，未修改 shell rc' }
        'chsrc' { 'source 已通过 chsrc 应用，并由原生命令验证' }
        'docker' { $result.Message }
        'chsrc-system' { '系统 package source 已通过 chsrc 应用，并纳入文件事务' }
    }
    $result | Add-Member -NotePropertyName Message -NotePropertyValue $message -Force
    return $result
}

function Get-PackageSourceCurrentState {
    <#
    .SYNOPSIS
        读取 adapter 可可靠识别的当前 source。

    .PARAMETER Target
        target 名称。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .OUTPUTS
        PSCustomObject 或 null。包含安全展示的 Source。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    switch ([string]$TargetConfig.adapter) {
        'chsrc' {
            return Get-ChsrcCommandPackageSourceState -Target $Target
        }
        'managed-env' {
            return Get-ManagedEnvPackageSourceState -TargetConfig $TargetConfig
        }
        default {
            return $null
        }
    }
}

function Test-PackageSourceIsOfficial {
    <#
    .SYNOPSIS
        判断当前 source 是否属于 catalog 明确列出的官方值。

    .PARAMETER Source
        当前 source URL。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .OUTPUTS
        bool。规范化 URL 与任一官方值相同时为 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    $normalizedSource = $Source.TrimEnd('/')
    foreach ($officialSource in @($TargetConfig.official_sources)) {
        if ([string]::Equals($normalizedSource, ([string]$officialSource).TrimEnd('/'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-PackageSourceAction {
    <#
    .SYNOPSIS
        执行统一 package source 动作。

    .DESCRIPTION
        作为 Switch-Mirrors.ps1 与后续平台薄包装之间的共享领域入口，返回稳定文档，
        由调用方选择文本或 JSON 序列化。

    .PARAMETER Action
        要执行的动作。

    .PARAMETER Mode
        Direct、China 或 Auto。

    .PARAMETER Phase
        Bootstrap、Runtime、Toolchain 或 Optional。

    .PARAMETER Target
        要处理的 target 列表。

    .PARAMETER TransactionId
        可选事务 ID。

    .PARAMETER Selection
        镜像选择策略。

    .PARAMETER Force
        仅人工 Restore 可用；发生 drift 时先备份当前文件再恢复。

    .PARAMETER MirrorUrl
        Docker adapter 的可选候选镜像覆盖。

    .PARAMETER TimeoutSeconds
        Docker 镜像探活超时秒数。

    .PARAMETER Retry
        Docker 镜像探活重试次数。

    .OUTPUTS
        PSCustomObject。包含顶层合同与逐 target 结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Plan', 'Apply', 'Ensure', 'Status', 'Restore')]
        [string]$Action,

        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$Mode = 'Direct',

        [ValidateSet('Bootstrap', 'Runtime', 'Toolchain', 'Optional')]
        [string]$Phase = 'Runtime',

        [string[]]$Target = @(),

        [string]$TransactionId = '',

        [string]$Selection = 'Auto',

        [switch]$Force,

        [string[]]$MirrorUrl = @(),

        [int]$TimeoutSeconds = 5,

        [int]$Retry = 1
    )

    Import-PackageSourceDependencies
    if ($Action -eq 'Status') {
        $stateRoot = Resolve-PackageSourceStateRoot
        $transactions = [System.Collections.Generic.List[hashtable]]::new()
        if (-not [string]::IsNullOrWhiteSpace($TransactionId)) {
            $transactions.Add((Open-PackageSourceTransaction -StateRoot $stateRoot -TransactionId $TransactionId))
        }
        elseif (Test-Path -LiteralPath $stateRoot -PathType Container) {
            foreach ($directory in Get-ChildItem -LiteralPath $stateRoot -Directory) {
                if (Test-Path -LiteralPath (Join-Path $directory.FullName 'manifest.json') -PathType Leaf) {
                    $transactions.Add((Open-PackageSourceTransaction -StateRoot $stateRoot -TransactionId $directory.Name))
                }
            }
        }

        $statusResults = [System.Collections.Generic.List[object]]::new()
        foreach ($statusTransaction in $transactions) {
            foreach ($statusResult in Get-PackageSourceTransactionStatusResult -Transaction $statusTransaction) {
                $statusResults.Add($statusResult)
            }
        }
        $statusMode = if ($transactions.Count -eq 1) { [string]$transactions[0].Manifest.Mode } else { $Mode }
        $statusNames = @($statusResults | ForEach-Object { [string]$_.Status })
        $statusExitCode = if (@($statusNames | Where-Object { $_ -in @('Drifted', 'Orphaned', 'RestoreFailed') }).Count -gt 0) {
            10
        }
        elseif ($statusNames -contains 'Failed') {
            1
        }
        else {
            0
        }
        return [PSCustomObject][ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = $statusMode
            TransactionId = $TransactionId
            ExitCode      = $statusExitCode
            Results       = $statusResults.ToArray()
        }
    }

    if ($Action -eq 'Restore') {
        if ([string]::IsNullOrWhiteSpace($TransactionId)) {
            throw 'Restore 必须提供 TransactionId'
        }

        $stateRoot = Resolve-PackageSourceStateRoot
        $stateLock = $null
        $transaction = $null
        try {
            $stateLock = Enter-PackageSourceStateLock -StateRoot $stateRoot
            $transaction = Open-PackageSourceTransaction -StateRoot $stateRoot -TransactionId $TransactionId
            $restoreResults = Restore-PackageSourceTransaction -Transaction $transaction -Force:$Force
        }
        catch {
            if ($null -ne $transaction) {
                $transaction.Manifest.Status = 'Drifted'
                $transaction.Manifest.LastError = $_.Exception.Message
                Write-PackageSourceTransactionManifest -Transaction $transaction
            }
            throw
        }
        finally {
            if ($null -ne $stateLock) {
                $stateLock.Dispose()
            }
        }

        return [PSCustomObject][ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = [string]$transaction.Manifest.Mode
            TransactionId = $TransactionId
            ExitCode      = 0
            Results       = $restoreResults
        }
    }

    if (-not $Target -or $Target.Count -eq 0) {
        throw 'Target 为必填参数'
    }

    $catalog = Get-PackageSourceCatalog
    $resolvedTargets = [System.Collections.Generic.List[object]]::new()
    foreach ($targetName in $Target) {
        $normalizedTarget = $targetName.Trim().ToLowerInvariant()
        if (-not $catalog.targets.Contains($normalizedTarget)) {
            throw "不支持的 package source target: $targetName"
        }

        $targetConfig = ConvertTo-ConfigHashtable -InputObject $catalog.targets[$normalizedTarget]
        $resolvedTargets.Add([PSCustomObject]@{
                Name   = $normalizedTarget
                Config = $targetConfig
            })
    }

    if ($Action -eq 'Ensure') {
        if ([string]::IsNullOrWhiteSpace($TransactionId)) {
            throw (New-PackageSourceException -Message 'Ensure 必须提供 TransactionId' -ExitCode 2 -Code 'InvalidArguments')
        }
        $ensureStateRoot = Resolve-PackageSourceStateRoot
        $ensureTransaction = Open-PackageSourceTransaction -StateRoot $ensureStateRoot -TransactionId $TransactionId
        $Mode = [string]$ensureTransaction.Manifest.Mode
    }

    $implementedAdapters = @('managed-env', 'chsrc', 'docker', 'chsrc-system')
    $unsupportedTargets = @($resolvedTargets | Where-Object { [string]$_.Config.adapter -notin $implementedAdapters })
    $results = [System.Collections.Generic.List[object]]::new()
    if ($Action -eq 'Plan' -or ($Mode -eq 'Direct' -and $Action -ne 'Ensure')) {
        $hasUnsupportedPlan = $false
        foreach ($targetEntry in $resolvedTargets) {
            if ($Mode -eq 'Direct') {
                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'Direct' -Message '保持当前 source，不执行探测或写入'))
            }
            elseif ([string]$targetEntry.Config.adapter -notin $implementedAdapters) {
                $reason = if ([string]::IsNullOrWhiteSpace([string]$targetEntry.Config.reason)) {
                    "adapter 尚未实现: $($targetEntry.Config.adapter)"
                }
                else {
                    [string]$targetEntry.Config.reason
                }
                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'Unsupported' -Message $reason -Persistent:($Mode -eq 'China')))
                $hasUnsupportedPlan = $true
            }
            else {
                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'Planned' -Message '计划在正式安装前应用 source adapter' -Persistent:($Mode -eq 'China')))
            }
        }

        return [PSCustomObject][ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = $Mode
            TransactionId = ''
            ExitCode      = if ($hasUnsupportedPlan) { 10 } else { 0 }
            Results       = $results.ToArray()
        }
    }

    if ($unsupportedTargets.Count -gt 0) {
        foreach ($targetEntry in $unsupportedTargets) {
            $reason = if ([string]::IsNullOrWhiteSpace([string]$targetEntry.Config.reason)) {
                "adapter 尚未实现: $($targetEntry.Config.adapter)"
            }
            else {
                [string]$targetEntry.Config.reason
            }
            $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'Unsupported' -Message $reason -Persistent:($Mode -eq 'China')))
        }

        return [PSCustomObject][ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = $Mode
            TransactionId = ''
            ExitCode      = 10
            Results       = $results.ToArray()
        }
    }

    if ($Action -notin @('Apply', 'Ensure') -or $Mode -notin @('China', 'Auto')) {
        throw "package source 动作尚未实现: Action=$Action, Mode=$Mode"
    }

    $targetsToApply = [System.Collections.Generic.List[object]]::new()
    $hasBlockedResult = $false
    if ($Mode -eq 'Auto' -and $Action -eq 'Apply') {
        $recoveryStateRoot = Resolve-PackageSourceStateRoot
        if (Test-Path -LiteralPath $recoveryStateRoot -PathType Container) {
            $recoveryLock = $null
            try {
                $recoveryLock = Enter-PackageSourceStateLock -StateRoot $recoveryStateRoot
                $null = Restore-OrphanedAutoTransaction -StateRoot $recoveryStateRoot -ExcludeTransactionId $TransactionId
            }
            finally {
                if ($null -ne $recoveryLock) {
                    $recoveryLock.Dispose()
                }
            }
        }

        $defaultConfig = ConvertTo-ConfigHashtable -InputObject $catalog.defaults
        foreach ($targetEntry in $resolvedTargets) {
            $currentState = Get-PackageSourceCurrentState -Target $targetEntry.Name -TargetConfig $targetEntry.Config
            if (
                $null -ne $currentState -and
                -not [string]::IsNullOrWhiteSpace([string]$currentState.Source) -and
                @($targetEntry.Config.official_sources).Count -gt 0 -and
                -not (Test-PackageSourceIsOfficial -Source ([string]$currentState.Source) -TargetConfig $targetEntry.Config)
            ) {
                $externalProbeConfig = @{
                    official_probe_urls = @([string]$currentState.Source)
                }
                $externalProbe = Test-PackageSourceOfficialEndpoint -TargetConfig $externalProbeConfig -TimeoutSeconds ([int]$defaultConfig.probe_timeout_seconds) -Attempts ([int]$defaultConfig.probe_attempts)
                if ($externalProbe.Healthy) {
                    $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'External' -Message '保留健康的未受本仓管理 source' -Source ([string]$currentState.Source)))
                    continue
                }

                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'ExternalUnavailable' -Message '未受本仓管理的自定义 source 不可用，拒绝自动覆盖' -Source ([string]$currentState.Source)))
                $hasBlockedResult = $true
                continue
            }

            $probe = Test-PackageSourceOfficialEndpoint -TargetConfig $targetEntry.Config -TimeoutSeconds ([int]$defaultConfig.probe_timeout_seconds) -Attempts ([int]$defaultConfig.probe_attempts)
            if ($probe.Healthy) {
                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter ([string]$targetEntry.Config.adapter) -Status 'Official' -Message $probe.Reason -Source $probe.Source))
            }
            else {
                $targetsToApply.Add($targetEntry)
            }
        }

        if ($targetsToApply.Count -eq 0) {
            return [PSCustomObject][ordered]@{
                SchemaVersion = 1
                Action        = $Action
                Mode          = $Mode
                TransactionId = ''
                ExitCode      = if ($hasBlockedResult) { 10 } else { 0 }
                Results       = $results.ToArray()
            }
        }
    }
    else {
        foreach ($targetEntry in $resolvedTargets) {
            $targetsToApply.Add($targetEntry)
        }
    }

    $effectiveTransactionId = if ([string]::IsNullOrWhiteSpace($TransactionId)) {
        New-PackageSourceTransactionId
    }
    else {
        $TransactionId
    }
    $stateRoot = Resolve-PackageSourceStateRoot
    $stateLock = $null
    $transaction = $null
    $resourcePathsByTarget = @{}

    try {
        $chsrcConfig = ConvertTo-ConfigHashtable -InputObject $catalog.chsrc
        $minimumChsrcVersion = [version]$chsrcConfig.minimum_version
        if (@($targetsToApply | Where-Object { [string]$_.Config.adapter -in @('managed-env', 'chsrc', 'chsrc-system') }).Count -gt 0) {
            $preflightChsrcPath = Resolve-ChsrcExecutablePath
            $null = Assert-ChsrcVersion -FilePath $preflightChsrcPath -MinimumVersion $minimumChsrcVersion
        }
        foreach ($targetEntry in $targetsToApply) {
            $resourcePathsByTarget[$targetEntry.Name] = @(Get-PackageSourceAdapterResourcePath -Target $targetEntry.Name -TargetConfig $targetEntry.Config)
        }
    }
    catch {
        if ($_.Exception.Data.Contains('ExitCode')) {
            throw
        }
        throw (New-PackageSourceException -Message $_.Exception.Message -ExitCode 10 -Code 'Blocked')
    }

    try {
        $stateLock = Enter-PackageSourceStateLock -StateRoot $stateRoot
        Assert-PackageSourceTransactionId -TransactionId $effectiveTransactionId
        $existingManifestPath = Join-Path (Join-Path $stateRoot $effectiveTransactionId) 'manifest.json'
        $transaction = if (Test-Path -LiteralPath $existingManifestPath -PathType Leaf) {
            Open-PackageSourceTransaction -StateRoot $stateRoot -TransactionId $effectiveTransactionId
        }
        elseif ($Action -eq 'Ensure') {
            throw (New-PackageSourceException -Message "Ensure 事务不存在: $effectiveTransactionId" -ExitCode 10 -Code 'Blocked')
        }
        else {
            New-PackageSourceTransaction -StateRoot $stateRoot -TransactionId $effectiveTransactionId -Mode $Mode
        }
        if ([string]$transaction.Manifest.Mode -ne $Mode) {
            throw (New-PackageSourceException -Message "事务模式不匹配: $effectiveTransactionId" -ExitCode 2 -Code 'InvalidArguments')
        }
        if ([string]$transaction.Manifest.Status -ne 'Active' -and [string]$transaction.Manifest.Status -ne 'Applying') {
            throw (New-PackageSourceException -Message "事务状态不允许继续 Apply: $($transaction.Manifest.Status)" -ExitCode 10 -Code 'Blocked')
        }

        foreach ($targetEntry in $targetsToApply) {
            $adapter = [string]$targetEntry.Config.adapter
            $resourcePaths = @($resourcePathsByTarget[$targetEntry.Name])
            $existingTargetValue = @($transaction.Manifest.Targets | Where-Object { [string]$_.Target -eq $targetEntry.Name } | Select-Object -First 1)
            if ($existingTargetValue.Count -gt 0) {
                $existingTarget = ConvertTo-ConfigHashtable -InputObject $existingTargetValue[0]
                $targetResources = @($transaction.Manifest.Resources | Where-Object { @($_.Targets) -contains $targetEntry.Name })
                if ($targetResources.Count -eq 0) {
                    throw (New-PackageSourceException -Message "事务缺少 target 资源记录: $($targetEntry.Name)" -ExitCode 10 -Code 'Blocked')
                }

                foreach ($resourceValue in $targetResources) {
                    $resource = ConvertTo-ConfigHashtable -InputObject $resourceValue
                    $currentHash = Get-PackageSourceFileHash -Path ([string]$resource.Path)
                    if ($currentHash -ne [string]$resource.AfterHash) {
                        throw (New-PackageSourceException -Message "已应用 target 发生 drift: $($targetEntry.Name)" -ExitCode 10 -Code 'Blocked')
                    }
                }

                $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter $adapter -Status 'AlreadyApplied' -Message '复用 active transaction，source 配置未重复写入' -Source ([string]$existingTarget.Source) -Persistent:($Mode -eq 'China') -TransactionId $effectiveTransactionId -Rollback "./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $effectiveTransactionId"))
                continue
            }

            $resources = [System.Collections.Generic.List[object]]::new()
            foreach ($resourcePath in $resourcePaths) {
                $resources.Add((Add-PackageSourceFileSnapshot -Transaction $transaction -Target $targetEntry.Name -Path $resourcePath))
            }
            Write-PackageSourceTransactionManifest -Transaction $transaction

            $adapterResult = Invoke-PackageSourceAdapterApply -Target $targetEntry.Name -TargetConfig $targetEntry.Config -MinimumChsrcVersion $minimumChsrcVersion -Selection $Selection -MirrorUrl $MirrorUrl -TimeoutSeconds $TimeoutSeconds -Retry $Retry
            foreach ($resource in $resources) {
                $resource.AfterHash = Get-PackageSourceFileHash -Path ([string]$resource.Path)
            }
            $targetRecord = [ordered]@{
                Target       = $targetEntry.Name
                Adapter      = $adapter
                Status       = if ($adapterResult.Changed) { 'Applied' } else { 'AlreadyApplied' }
                Source       = $adapterResult.Source
                ChsrcVersion = $adapterResult.ChsrcVersion
                AppliedAt    = [DateTime]::UtcNow.ToString('o')
            }
            $transaction.Manifest.Targets = @($transaction.Manifest.Targets) + @($targetRecord)
            Write-PackageSourceTransactionManifest -Transaction $transaction

            $results.Add((New-PackageSourceResult -Target $targetEntry.Name -Mode $Mode -Phase $Phase -Adapter $adapter -Status $targetRecord.Status -Message $adapterResult.Message -Source $adapterResult.Source -Persistent:($Mode -eq 'China') -TransactionId $effectiveTransactionId -Rollback "./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $effectiveTransactionId"))
        }

        $transaction.Manifest.Status = 'Active'
        Write-PackageSourceTransactionManifest -Transaction $transaction
    }
    catch {
        if ($null -ne $transaction) {
            if ($Mode -eq 'Auto') {
                $applyError = $_
                try {
                    foreach ($resource in @($transaction.Manifest.Resources)) {
                        $resource.AfterHash = Get-PackageSourceFileHash -Path ([string]$resource.Path)
                    }
                    $null = Restore-PackageSourceTransaction -Transaction $transaction
                }
                catch {
                    $transaction.Manifest.Status = 'RestoreFailed'
                    $transaction.Manifest.LastError = $_.Exception.Message
                    Write-PackageSourceTransactionManifest -Transaction $transaction
                }
                throw $applyError
            }

            $transaction.Manifest.Status = 'Failed'
            $transaction.Manifest.LastError = $_.Exception.Message
            Write-PackageSourceTransactionManifest -Transaction $transaction
        }
        throw
    }
    finally {
        if ($null -ne $stateLock) {
            $stateLock.Dispose()
        }
    }

    return [PSCustomObject][ordered]@{
        SchemaVersion = 1
        Action        = $Action
        Mode          = $Mode
        TransactionId = $effectiveTransactionId
        ExitCode      = if ($hasBlockedResult) { 10 } else { 0 }
        Results       = $results.ToArray()
    }
}

Export-ModuleMember -Function @(
    'Get-PackageSourceCatalog'
    'Invoke-PackageSourceAction'
)
