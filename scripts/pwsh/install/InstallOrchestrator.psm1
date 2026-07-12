Set-StrictMode -Version Latest

$script:SupportedPresets = @('Core', 'Full')
$script:SupportedPlatforms = @('macos', 'linux', 'windows')
$script:SupportedRunners = @('pwsh', 'bash', 'zsh')

function Test-InstallStepRegistry {
    <#
    .SYNOPSIS
        校验安装步骤注册表的结构与依赖图。

    .PARAMETER Registry
        通过 PowerShell data file 读取的注册表。

    .OUTPUTS
        System.Boolean。校验通过时返回 $true；失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry
    )

    if ([int]$Registry.SchemaVersion -ne 1) {
        throw "不支持的安装步骤 schema version: $($Registry.SchemaVersion)"
    }

    $steps = @($Registry.Steps)
    if ($steps.Count -eq 0) {
        throw '安装步骤注册表不能为空'
    }

    $idSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $numberSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $previousNumber = -1
    foreach ($step in $steps) {
        $id = [string]$step.Id
        $number = [string]$step.Number
        if ([string]::IsNullOrWhiteSpace($id) -or -not $idSet.Add($id)) {
            throw "安装步骤 ID 重复或为空: $id"
        }
        if ($number -notmatch '^\d{2}$' -or -not $numberSet.Add($number)) {
            throw "安装步骤编号重复或非法: $number"
        }

        $numericNumber = [int]$number
        if ($numericNumber -le $previousNumber) {
            throw "安装步骤编号必须稳定递增: $number"
        }
        $previousNumber = $numericNumber

        $presets = @($step.Presets)
        if ($presets.Count -eq 0 -or @($presets | Where-Object { $_ -notin $script:SupportedPresets }).Count -gt 0) {
            throw "安装步骤 $id 包含未知 Preset"
        }

        foreach ($platform in $script:SupportedPlatforms) {
            if (-not $step.Platforms.ContainsKey($platform)) {
                throw "安装步骤 $id 缺少平台声明: $platform"
            }
            $platformEntry = $step.Platforms[$platform]
            if ([bool]$platformEntry.Supported) {
                if ([string]::IsNullOrWhiteSpace([string]$platformEntry.Path)) {
                    throw "安装步骤 $id 的 $platform 入口缺少 Path"
                }
                if ([string]$platformEntry.Runner -notin $script:SupportedRunners) {
                    throw "安装步骤 $id 的 $platform 入口包含未知 Runner"
                }
            }
        }
    }

    foreach ($step in $steps) {
        foreach ($dependency in @($step.DependsOn)) {
            if (-not $idSet.Contains([string]$dependency)) {
                throw "安装步骤 $($step.Id) 包含未知依赖: $dependency"
            }
        }
    }

    $visiting = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stepMap = @{}
    foreach ($step in $steps) {
        $stepMap[[string]$step.Id] = $step
    }

    $visitStep = {
        param([string]$StepId)

        if ($visited.Contains($StepId)) {
            return
        }
        if (-not $visiting.Add($StepId)) {
            throw "安装步骤依赖存在循环: $StepId"
        }
        foreach ($dependency in @($stepMap[$StepId].DependsOn)) {
            & $visitStep ([string]$dependency)
        }
        $null = $visiting.Remove($StepId)
        $null = $visited.Add($StepId)
    }

    foreach ($step in $steps) {
        & $visitStep ([string]$step.Id)
    }

    return $true
}

function Import-InstallStepRegistry {
    <#
    .SYNOPSIS
        读取并校验安装步骤注册表。

    .PARAMETER Path
        `steps.psd1` 文件路径。

    .OUTPUTS
        System.Collections.Hashtable。校验后的注册表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "安装步骤注册表不存在: $Path"
    }
    $registry = Import-PowerShellDataFile -LiteralPath $Path
    $null = Test-InstallStepRegistry -Registry $registry
    return $registry
}

function Assert-InstallStepIds {
    <#
    .SYNOPSIS
        校验步骤 ID 是否属于指定 Preset。

    .PARAMETER StepIds
        待校验的步骤 ID。

    .PARAMETER PresetSteps
        指定 Preset 的全部步骤。

    .OUTPUTS
        None。校验失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [string[]]$StepIds,

        [Parameter(Mandatory)]
        [object[]]$PresetSteps
    )

    $validIds = @($PresetSteps | ForEach-Object { [string]$_.Id })
    foreach ($stepId in @($StepIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        if ($stepId -notin $validIds) {
            throw "未知安装步骤或步骤不属于所选 Preset: $stepId"
        }
    }
}

function Select-InstallStepPlan {
    <#
    .SYNOPSIS
        根据 Preset 和步骤过滤参数生成稳定执行计划。

    .PARAMETER Registry
        已校验的安装步骤注册表。

    .PARAMETER Preset
        Core 或 Full。

    .PARAMETER Step
        只选择明确指定的步骤，不展开依赖。

    .PARAMETER FromStep
        从指定步骤开始选择 Preset 后续步骤。

    .PARAMETER SkipStep
        从执行计划中排除的步骤。

    .OUTPUTS
        PSCustomObject[]。按稳定编号排序的步骤计划。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Full')]
        [string]$Preset,

        [string[]]$Step,

        [string]$FromStep = '',

        [string[]]$SkipStep
    )

    $normalizedSteps = @($Step | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $normalizedSkipSteps = @($SkipStep | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($normalizedSteps.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($FromStep)) {
        throw 'Step 与 FromStep 不能同时使用'
    }

    $presetSteps = @($Registry.Steps | Where-Object { $Preset -in @($_.Presets) })
    Assert-InstallStepIds -StepIds $normalizedSteps -PresetSteps $presetSteps
    Assert-InstallStepIds -StepIds $normalizedSkipSteps -PresetSteps $presetSteps
    if (-not [string]::IsNullOrWhiteSpace($FromStep)) {
        Assert-InstallStepIds -StepIds @($FromStep) -PresetSteps $presetSteps
    }

    $selected = $presetSteps
    $dependenciesVerified = $true
    if ($normalizedSteps.Count -gt 0) {
        $selected = @($presetSteps | Where-Object { $_.Id -in $normalizedSteps })
        $dependenciesVerified = $false
    }
    elseif (-not [string]::IsNullOrWhiteSpace($FromStep)) {
        $startIndex = [array]::IndexOf(@($presetSteps.Id), $FromStep)
        $selected = @($presetSteps[$startIndex..($presetSteps.Count - 1)])
    }

    if ($normalizedSkipSteps.Count -gt 0) {
        $selected = @($selected | Where-Object { $_.Id -notin $normalizedSkipSteps })
    }

    return @($selected | ForEach-Object {
            [pscustomobject]@{
                Id                        = [string]$_.Id
                Number                    = [string]$_.Number
                Presets                   = @($_.Presets)
                DependsOn                 = @($_.DependsOn)
                Platforms                 = $_.Platforms
                DependenciesVerifiedInRun = $dependenciesVerified
            }
        })
}

function Get-InstallStepCatalog {
    <#
    .SYNOPSIS
        返回可供 CLI 列出的安装步骤目录。

    .PARAMETER Registry
        已校验的安装步骤注册表。

    .PARAMETER Platform
        规范化平台名称。

    .OUTPUTS
        PSCustomObject[]。步骤目录及平台支持信息。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter(Mandatory)]
        [ValidateSet('macos', 'linux', 'windows')]
        [string]$Platform
    )

    return @($Registry.Steps | ForEach-Object {
            $platformEntry = $_.Platforms[$Platform]
            [pscustomobject]@{
                Id        = [string]$_.Id
                Number    = [string]$_.Number
                Presets   = @($_.Presets)
                DependsOn = @($_.DependsOn)
                Supported = [bool]$platformEntry.Supported
                Path      = if ($platformEntry.ContainsKey('Path')) { [string]$platformEntry.Path } else { '' }
                Runner    = if ($platformEntry.ContainsKey('Runner')) { [string]$platformEntry.Runner } else { '' }
            }
        })
}

function Resolve-InstallPlatform {
    <#
    .SYNOPSIS
        把 PowerShell 平台变量规范化为注册表平台名称。

    .PARAMETER Platform
        可选的平台覆盖值，主要供确定性测试使用。

    .OUTPUTS
        System.String。返回 macos、linux 或 windows。
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('', 'macos', 'linux', 'windows')]
        [string]$Platform = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        return $Platform
    }
    if ($IsWindows) {
        return 'windows'
    }
    if ($IsMacOS) {
        return 'macos'
    }
    if ($IsLinux) {
        return 'linux'
    }
    throw "不支持的平台: $($PSVersionTable.OS)"
}

function Get-InstallLeafArguments {
    <#
    .SYNOPSIS
        根据步骤和 runner 生成叶子参数数组。

    .PARAMETER StepId
        安装步骤 ID。

    .PARAMETER PlatformEntry
        注册表中的平台入口声明。

    .PARAMETER Preset
        Core 或 Full。

    .PARAMETER NetworkMode
        Direct、China 或 Auto。

    .PARAMETER TransactionId
        package source 事务 ID。

    .PARAMETER Preview
        是否透传预览参数。

    .PARAMETER Unattended
        是否透传无人值守参数。

    .PARAMETER NonInteractive
        是否透传严格非交互参数。

    .OUTPUTS
        System.String[]。安全传给 ProcessStartInfo.ArgumentList 的参数。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [hashtable]$PlatformEntry,

        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Full')]
        [string]$Preset,

        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$NetworkMode = 'Direct',

        [string]$TransactionId = '',

        [switch]$Preview,

        [switch]$Unattended,

        [switch]$NonInteractive
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $isPowerShell = [string]$PlatformEntry.Runner -eq 'pwsh'
    if ($StepId -eq 'sources') {
        $arguments.Add($(if ($isPowerShell) { '-NetworkMode' } else { '--network-mode' }))
        $arguments.Add($NetworkMode)
        $arguments.Add($(if ($isPowerShell) { '-TransactionId' } else { '--transaction-id' }))
        $arguments.Add($TransactionId)
        $arguments.Add($(if ($isPowerShell) { '-OutputFormat' } else { '--output-format' }))
        $arguments.Add($(if ($isPowerShell) { 'Json' } else { 'json' }))
    }
    else {
        $arguments.Add($(if ($isPowerShell) { '-Preset' } else { '--preset' }))
        $arguments.Add($Preset)
        if ($StepId -eq 'platform-automation' -and $isPowerShell) {
            $arguments.Add('-NetworkMode')
            $arguments.Add($NetworkMode)
        }
    }

    if ($Unattended) {
        $arguments.Add($(if ($isPowerShell) { '-Unattended' } else { '--unattended' }))
    }
    if ($NonInteractive) {
        $arguments.Add($(if ($isPowerShell) { '-NonInteractive' } else { '--non-interactive' }))
    }
    if ($Preview -and $PlatformEntry.ContainsKey('PreviewArgument')) {
        $previewArgument = [string]$PlatformEntry.PreviewArgument
        if (-not [string]::IsNullOrWhiteSpace($previewArgument)) {
            $arguments.Add($previewArgument)
        }
    }

    return $arguments.ToArray()
}

function Format-InstallCommand {
    <#
    .SYNOPSIS
        生成仅供日志和结果展示的命令文本。

    .PARAMETER Executable
        实际 runner 可执行文件。

    .PARAMETER Arguments
        参数数组。

    .OUTPUTS
        System.String。不会用于实际执行的展示文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [string[]]$Arguments
    )

    $displayArguments = @($Arguments | ForEach-Object {
            $value = [string]$_
            if ($value -match '\s') {
                '"{0}"' -f $value.Replace('"', '\"')
            }
            else {
                $value
            }
        })
    return (@($Executable) + $displayArguments) -join ' '
}

function Protect-InstallDiagnostic {
    <#
    .SYNOPSIS
        截断并脱敏叶子进程诊断摘要。

    .PARAMETER Text
        原始 stdout 或 stderr。

    .PARAMETER MaxLength
        最大保留字符数。

    .OUTPUTS
        System.String。可进入稳定结果的诊断摘要。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [ValidateRange(64, 8192)]
        [int]$MaxLength = 1024
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }
    $protected = $Text.Trim() -replace '(?i)(token|password|secret|api[_-]?key)=([^\s&]+)', '$1=[REDACTED]'
    if ($protected.Length -le $MaxLength) {
        return $protected
    }
    return $protected.Substring(0, $MaxLength) + '...'
}

function Invoke-InstallLeafProcess {
    <#
    .SYNOPSIS
        使用参数数组在隔离子进程中执行平台叶子。

    .PARAMETER Runner
        pwsh、bash 或 zsh。

    .PARAMETER ScriptPath
        叶子脚本绝对路径。

    .PARAMETER ArgumentList
        透传给叶子的参数数组。

    .OUTPUTS
        PSCustomObject。包含退出码、stdout、stderr、耗时和展示命令。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pwsh', 'bash', 'zsh')]
        [string]$Runner,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [string[]]$ArgumentList
    )

    $runnerCommand = Get-Command $Runner -ErrorAction Stop
    $processArguments = [System.Collections.Generic.List[string]]::new()
    if ($Runner -eq 'pwsh') {
        $processArguments.Add('-NoProfile')
        $processArguments.Add('-File')
    }
    $processArguments.Add($ScriptPath)
    foreach ($argument in @($ArgumentList)) {
        $processArguments.Add([string]$argument)
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $runnerCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($argument in $processArguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) {
            throw "无法启动安装叶子: $ScriptPath"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $stopwatch.Stop()
        return [pscustomobject]@{
            ExitCode   = $process.ExitCode
            Stdout     = $stdout
            Stderr     = $stderr
            DurationMs = [long]$stopwatch.ElapsedMilliseconds
            Command    = Format-InstallCommand -Executable $runnerCommand.Source -Arguments $processArguments.ToArray()
        }
    }
    finally {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $process.Dispose()
    }
}

function Invoke-InstallSourceRestore {
    <#
    .SYNOPSIS
        通过共享 package source 入口恢复 Auto 事务。

    .PARAMETER RepoRoot
        仓库根目录。

    .PARAMETER TransactionId
        需要恢复的 package source 事务 ID。

    .OUTPUTS
        PSCustomObject。包含恢复退出码、诊断、耗时和展示命令。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$TransactionId
    )

    $restorePath = Join-Path $RepoRoot 'scripts/pwsh/misc/Switch-Mirrors.ps1'
    if (-not (Test-Path -LiteralPath $restorePath -PathType Leaf)) {
        throw "package source 恢复入口不存在: $restorePath"
    }

    $processResult = Invoke-InstallLeafProcess `
        -Runner pwsh `
        -ScriptPath $restorePath `
        -ArgumentList @(
            '-Action', 'Restore',
            '-TransactionId', $TransactionId,
            '-OutputFormat', 'Json'
        )

    $messageSource = if (-not [string]::IsNullOrWhiteSpace($processResult.Stderr)) {
        $processResult.Stderr
    }
    else {
        $processResult.Stdout
    }
    $message = Protect-InstallDiagnostic -Text $messageSource
    if ($processResult.ExitCode -eq 0) {
        try {
            $restoreDocument = $processResult.Stdout | ConvertFrom-Json -ErrorAction Stop
            if ([int]$restoreDocument.ExitCode -ne 0) {
                $processResult.ExitCode = [int]$restoreDocument.ExitCode
            }
        }
        catch {
            $processResult.ExitCode = 1
            $message = "无法解析 source Restore JSON 输出: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        ExitCode   = [int]$processResult.ExitCode
        DurationMs = [long]$processResult.DurationMs
        Message    = $message
        Command    = [string]$processResult.Command
    }
}

function New-InstallRetryCommand {
    <#
    .SYNOPSIS
        生成可复制的安装步骤重跑命令。

    .PARAMETER Preset
        Core 或 Full。

    .PARAMETER SelectorName
        Step 或 FromStep。

    .PARAMETER StepId
        重跑起点步骤 ID。

    .PARAMETER NetworkMode
        Direct、China 或 Auto。

    .PARAMETER Preview
        是否保留 WhatIf 预览语义。

    .PARAMETER Unattended
        是否保留无人值守语义。

    .PARAMETER NonInteractive
        是否保留严格非交互语义。

    .OUTPUTS
        System.String。仅用于展示，不参与实际执行。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Full')]
        [string]$Preset,

        [Parameter(Mandatory)]
        [ValidateSet('Step', 'FromStep')]
        [string]$SelectorName,

        [Parameter(Mandatory)]
        [string]$StepId,

        [Parameter(Mandatory)]
        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$NetworkMode,

        [switch]$Preview,

        [switch]$Unattended,

        [switch]$NonInteractive
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('./install.ps1')
    $parts.Add('-Preset')
    $parts.Add($Preset)
    $parts.Add("-$SelectorName")
    $parts.Add($StepId)
    $parts.Add('-NetworkMode')
    $parts.Add($NetworkMode)
    if ($Unattended) {
        $parts.Add('-Unattended')
    }
    if ($NonInteractive) {
        $parts.Add('-NonInteractive')
    }
    if ($Preview) {
        $parts.Add('-WhatIf')
    }
    return $parts -join ' '
}

function New-InstallStepResult {
    <#
    .SYNOPSIS
        创建稳定的安装步骤结果对象。

    .PARAMETER Step
        执行计划中的步骤。

    .PARAMETER Status
        Succeeded、Preview、Skipped、Failed 或 Blocked。

    .PARAMETER ExitCode
        叶子或编排状态退出码。

    .PARAMETER DurationMs
        执行耗时毫秒数。

    .PARAMETER Message
        结果摘要。

    .PARAMETER Command
        仅供展示的安全命令文本。

    .PARAMETER Preset
        用于生成重跑命令的 Preset。

    .OUTPUTS
        PSCustomObject。稳定步骤结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Step,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'Preview', 'Skipped', 'Failed', 'Blocked')]
        [string]$Status,

        [int]$ExitCode = 0,

        [long]$DurationMs = 0,

        [string]$Message = '',

        [string]$Command = '',

        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Full')]
        [string]$Preset
    )

    $rerunCommand = if ($Status -in @('Failed', 'Blocked')) {
        "./install.ps1 -Preset $Preset -Step $($Step.Id)"
    }
    else {
        ''
    }
    return [pscustomobject]@{
        Id                        = $Step.Id
        Number                    = $Step.Number
        Status                    = $Status
        ExitCode                  = $ExitCode
        DurationMs                = $DurationMs
        Message                   = $Message
        DependsOn                 = @($Step.DependsOn)
        DependenciesVerifiedInRun = [bool]$Step.DependenciesVerifiedInRun
        Command                   = $Command
        RerunCommand              = $rerunCommand
    }
}

function Get-InstallRunStatus {
    <#
    .SYNOPSIS
        根据步骤结果计算整体状态与退出码。

    .PARAMETER Results
        安装步骤结果数组。

    .OUTPUTS
        PSCustomObject。包含 Status 与 ExitCode。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    if (@($Results | Where-Object Status -eq 'Failed').Count -gt 0) {
        return [pscustomobject]@{ Status = 'Failed'; ExitCode = 1 }
    }
    if (@($Results | Where-Object Status -eq 'Blocked').Count -gt 0) {
        return [pscustomobject]@{ Status = 'Blocked'; ExitCode = 10 }
    }
    return [pscustomobject]@{ Status = 'Succeeded'; ExitCode = 0 }
}

function Invoke-InstallOrchestrator {
    <#
    .SYNOPSIS
        执行选定的 Stage 1 安装步骤并返回结构化汇总。

    .PARAMETER Registry
        已加载或测试注入的安装步骤注册表。

    .PARAMETER RepoRoot
        仓库根目录，用于解析叶子相对路径。

    .PARAMETER Platform
        macos、linux 或 windows。

    .PARAMETER Preset
        Core 或 Full。

    .PARAMETER Step
        精确执行的步骤 ID。

    .PARAMETER FromStep
        从指定步骤开始执行 Preset 尾部。

    .PARAMETER SkipStep
        排除的步骤 ID。

    .PARAMETER NetworkMode
        Direct、China 或 Auto。

    .PARAMETER Preview
        是否以预览模式执行叶子。

    .PARAMETER Unattended
        是否使用无人值守模式。

    .PARAMETER NonInteractive
        是否使用严格非交互模式。

    .OUTPUTS
        PSCustomObject。稳定安装运行 document。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateSet('macos', 'linux', 'windows')]
        [string]$Platform,

        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Full')]
        [string]$Preset,

        [string[]]$Step,

        [string]$FromStep = '',

        [string[]]$SkipStep,

        [ValidateSet('Direct', 'China', 'Auto')]
        [string]$NetworkMode = 'Direct',

        [switch]$Preview,

        [switch]$Unattended,

        [switch]$NonInteractive
    )

    $null = Test-InstallStepRegistry -Registry $Registry
    $plan = @(Select-InstallStepPlan -Registry $Registry -Preset $Preset -Step $Step -FromStep $FromStep -SkipStep $SkipStep)
    $runId = "install-{0}-{1}" -f [DateTime]::UtcNow.ToString('yyyyMMddHHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8)
    $transactionId = "{0}-sources" -f $runId
    $startedAt = [DateTime]::UtcNow
    $results = [System.Collections.Generic.List[object]]::new()
    $resultById = @{}
    $skippedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($skippedId in @($SkipStep | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $null = $skippedIds.Add([string]$skippedId)
    }
    $sourceTransactionId = ''
    $rollback = ''
    $sourceRestore = [pscustomobject]@{
        Attempted  = $false
        Status     = 'NotRequired'
        ExitCode   = 0
        DurationMs = 0
        Message    = ''
        Command    = ''
    }

    try {
        foreach ($planStep in $plan) {
        $platformEntry = $planStep.Platforms[$Platform]
        if (-not [bool]$platformEntry.Supported) {
            $result = New-InstallStepResult -Step $planStep -Status Skipped -Message "平台 $Platform 不支持该步骤" -Preset $Preset
            $results.Add($result)
            $resultById[$planStep.Id] = $result
            continue
        }

        $blockedDependencies = [System.Collections.Generic.List[string]]::new()
        if ($planStep.DependenciesVerifiedInRun) {
            foreach ($dependency in @($planStep.DependsOn)) {
                if ($skippedIds.Contains([string]$dependency)) {
                    $blockedDependencies.Add([string]$dependency)
                    continue
                }
                if ($resultById.ContainsKey([string]$dependency) -and $resultById[[string]$dependency].Status -notin @('Succeeded', 'Preview')) {
                    $blockedDependencies.Add([string]$dependency)
                }
            }
        }
        if ($blockedDependencies.Count -gt 0) {
            $message = "依赖步骤未成功: {0}" -f ($blockedDependencies -join ', ')
            $result = New-InstallStepResult -Step $planStep -Status Blocked -ExitCode 10 -Message $message -Preset $Preset
            $results.Add($result)
            $resultById[$planStep.Id] = $result
            continue
        }

        $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$platformEntry.Path)))
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $result = New-InstallStepResult -Step $planStep -Status Blocked -ExitCode 10 -Message "平台叶子入口不存在: $scriptPath" -Preset $Preset
            $results.Add($result)
            $resultById[$planStep.Id] = $result
            continue
        }

        $arguments = Get-InstallLeafArguments `
            -StepId $planStep.Id `
            -PlatformEntry $platformEntry `
            -Preset $Preset `
            -NetworkMode $NetworkMode `
            -TransactionId $transactionId `
            -Preview:$Preview `
            -Unattended:$Unattended `
            -NonInteractive:$NonInteractive
        try {
            $processResult = Invoke-InstallLeafProcess -Runner ([string]$platformEntry.Runner) -ScriptPath $scriptPath -ArgumentList $arguments
            $status = switch ($processResult.ExitCode) {
                0 { if ($Preview) { 'Preview' } else { 'Succeeded' } }
                10 { 'Blocked' }
                default { 'Failed' }
            }
            $messageSource = if (-not [string]::IsNullOrWhiteSpace($processResult.Stderr)) { $processResult.Stderr } else { $processResult.Stdout }
            $message = Protect-InstallDiagnostic -Text $messageSource

            if ($planStep.Id -eq 'sources' -and -not [string]::IsNullOrWhiteSpace($processResult.Stdout)) {
                try {
                    $sourceDocument = $processResult.Stdout | ConvertFrom-Json -ErrorAction Stop
                    if (-not $Preview) {
                        $sourceTransactionId = [string]$sourceDocument.TransactionId
                        $rollbackProperty = $sourceDocument.PSObject.Properties['Rollback']
                        if ($null -ne $rollbackProperty) {
                            $rollback = [string]$rollbackProperty.Value
                        }
                        elseif ($sourceDocument.PSObject.Properties['Results']) {
                            $rollbackCandidates = @($sourceDocument.Results | ForEach-Object {
                                    $resultRollbackProperty = $_.PSObject.Properties['Rollback']
                                    if ($null -ne $resultRollbackProperty -and
                                        -not [string]::IsNullOrWhiteSpace([string]$resultRollbackProperty.Value)) {
                                        [string]$resultRollbackProperty.Value
                                    }
                                })
                            if ($rollbackCandidates.Count -gt 0) {
                                $rollback = [string]$rollbackCandidates[0]
                            }
                        }
                    }
                    if ($processResult.ExitCode -eq 0 -and [int]$sourceDocument.ExitCode -ne 0) {
                        $processResult.ExitCode = [int]$sourceDocument.ExitCode
                        $status = if ($processResult.ExitCode -eq 10) { 'Blocked' } else { 'Failed' }
                    }
                    if (-not $Preview -and $NetworkMode -eq 'China' -and [string]::IsNullOrWhiteSpace($sourceTransactionId)) {
                        $status = 'Failed'
                        $processResult.ExitCode = 1
                        $message = 'China source 步骤成功后未返回可恢复的事务 ID'
                    }
                }
                catch {
                    if ($processResult.ExitCode -eq 0) {
                        $status = 'Failed'
                        $message = "无法解析 sources JSON 输出: $($_.Exception.Message)"
                        $processResult.ExitCode = 1
                    }
                }
            }

            $resultExitCode = if ($status -eq 'Blocked') { 10 } elseif ($status -eq 'Failed') { 1 } else { 0 }
            $result = New-InstallStepResult `
                -Step $planStep `
                -Status $status `
                -ExitCode $resultExitCode `
                -DurationMs $processResult.DurationMs `
                -Message $message `
                -Command $processResult.Command `
                -Preset $Preset
        }
        catch {
            $result = New-InstallStepResult -Step $planStep -Status Failed -ExitCode 1 -Message (Protect-InstallDiagnostic -Text $_.Exception.Message) -Preset $Preset
        }
        $results.Add($result)
        $resultById[$planStep.Id] = $result
        }
    }
    finally {
        if ($NetworkMode -eq 'Auto' -and -not $Preview -and -not [string]::IsNullOrWhiteSpace($sourceTransactionId)) {
            $sourceRestore.Attempted = $true
            try {
                $restoreResult = Invoke-InstallSourceRestore -RepoRoot $RepoRoot -TransactionId $sourceTransactionId
                $sourceRestore.ExitCode = [int]$restoreResult.ExitCode
                $sourceRestore.DurationMs = [long]$restoreResult.DurationMs
                $sourceRestore.Message = [string]$restoreResult.Message
                $sourceRestore.Command = [string]$restoreResult.Command
                if ($restoreResult.ExitCode -eq 0) {
                    $sourceRestore.Status = 'Succeeded'
                    $rollback = ''
                }
                else {
                    $sourceRestore.Status = 'Blocked'
                    $sourceRestore.ExitCode = 10
                    $rollback = "./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $sourceTransactionId"
                }
            }
            catch {
                $sourceRestore.Status = 'Blocked'
                $sourceRestore.ExitCode = 10
                $sourceRestore.Message = Protect-InstallDiagnostic -Text $_.Exception.Message
                $rollback = "./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId $sourceTransactionId"
            }
        }
    }

    $finishedAt = [DateTime]::UtcNow
    $runStatus = Get-InstallRunStatus -Results $results.ToArray()
    if ($sourceRestore.Status -eq 'Blocked' -and $runStatus.Status -ne 'Failed') {
        $runStatus = [pscustomobject]@{ Status = 'Blocked'; ExitCode = 10 }
    }

    $retryCandidates = @($results | Where-Object { $_.Status -in @('Failed', 'Blocked') })
    foreach ($retryResult in $retryCandidates) {
        $retryResult.RerunCommand = New-InstallRetryCommand `
            -Preset $Preset `
            -SelectorName Step `
            -StepId ([string]$retryResult.Id) `
            -NetworkMode $NetworkMode `
            -Preview:$Preview `
            -Unattended:$Unattended `
            -NonInteractive:$NonInteractive
    }
    $continueCommand = if ($retryCandidates.Count -gt 0) {
        New-InstallRetryCommand `
            -Preset $Preset `
            -SelectorName FromStep `
            -StepId ([string]$retryCandidates[0].Id) `
            -NetworkMode $NetworkMode `
            -Preview:$Preview `
            -Unattended:$Unattended `
            -NonInteractive:$NonInteractive
    }
    else {
        ''
    }

    return [pscustomobject]@{
        SchemaVersion       = 1
        RunId               = $runId
        Platform            = $Platform
        Preset              = $Preset
        NetworkMode         = $NetworkMode
        Preview             = [bool]$Preview
        Status              = $runStatus.Status
        ExitCode            = $runStatus.ExitCode
        StartedAt           = $startedAt.ToString('o')
        FinishedAt          = $finishedAt.ToString('o')
        DurationMs          = [long]($finishedAt - $startedAt).TotalMilliseconds
        Results             = $results.ToArray()
        SourceTransactionId = $sourceTransactionId
        SourceRestore       = $sourceRestore
        Rollback            = $rollback
        ContinueCommand     = $continueCommand
    }
}

function ConvertTo-InstallRunJson {
    <#
    .SYNOPSIS
        把安装运行 document 序列化为单个 JSON 文档。

    .PARAMETER Document
        Invoke-InstallOrchestrator 返回的运行 document。

    .OUTPUTS
        System.String。稳定 JSON 文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject]$Document
    )

    process {
        return ($Document | ConvertTo-Json -Depth 20)
    }
}

function Write-InstallRunText {
    <#
    .SYNOPSIS
        以人工可读格式输出安装运行汇总。

    .PARAMETER Document
        Invoke-InstallOrchestrator 返回的运行 document。

    .OUTPUTS
        None。文本直接写入标准输出。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Document
    )

    [Console]::Out.WriteLine("Stage 1: platform={0} preset={1} network={2}" -f $Document.Platform, $Document.Preset, $Document.NetworkMode)
    foreach ($result in @($Document.Results)) {
        [Console]::Out.WriteLine("[{0}] {1} {2} ({3}ms)" -f $result.Status, $result.Number, $result.Id, $result.DurationMs)
        if (-not [string]::IsNullOrWhiteSpace([string]$result.Message)) {
            [Console]::Out.WriteLine("  {0}" -f $result.Message)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$result.RerunCommand)) {
            [Console]::Out.WriteLine("  retry: {0}" -f $result.RerunCommand)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Document.Rollback)) {
        [Console]::Out.WriteLine("rollback: {0}" -f $Document.Rollback)
    }
    if ([bool]$Document.SourceRestore.Attempted) {
        [Console]::Out.WriteLine("[{0}] source-restore ({1}ms)" -f $Document.SourceRestore.Status, $Document.SourceRestore.DurationMs)
        if (-not [string]::IsNullOrWhiteSpace([string]$Document.SourceRestore.Message)) {
            [Console]::Out.WriteLine("  {0}" -f $Document.SourceRestore.Message)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Document.ContinueCommand)) {
        [Console]::Out.WriteLine("continue: {0}" -f $Document.ContinueCommand)
    }
    [Console]::Out.WriteLine("Result: status={0} exitCode={1}" -f $Document.Status, $Document.ExitCode)
}

Export-ModuleMember -Function @(
    'ConvertTo-InstallRunJson',
    'Get-InstallStepCatalog',
    'Import-InstallStepRegistry',
    'Invoke-InstallOrchestrator',
    'Resolve-InstallPlatform',
    'Select-InstallStepPlan',
    'Test-InstallStepRegistry',
    'Write-InstallRunText'
)
