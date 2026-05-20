#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按配置同步安装 agent skills 与配套工具。

.DESCRIPTION
    读取 `skills.config.json`，生成 skills CLI 安装计划，并调用 `npx skills add`
    将远程或本地开发 skill 安装到指定 agent。脚本同时支持配置 tool setup，
    用于 Context7 这类不是通过 `skills add` 安装的工具。

.PARAMETER ConfigPath
    JSON 配置文件路径；默认读取脚本目录下的 `skills.config.json`。

.PARAMETER Agent
    覆盖配置中的默认 agent 列表；支持 `claude`、`codex` 等友好名称。

.PARAMETER Name
    只处理指定 skill 或 tool 名称；未指定时处理配置中的全部项目。

.PARAMETER IncludeDevAll
    自动发现 `dev/*/SKILL.md` 并把未显式配置的本地开发 skill 纳入安装计划。

.PARAMETER DryRun
    只展示安装计划，不执行外部命令。

.PARAMETER Yes
    跳过脚本级安装计划确认，适合多设备同步或 CI 场景。

.PARAMETER Force
    明确表示即使目标可能已存在也继续执行安装命令；实际覆盖语义由 CLI 决定。

.PARAMETER LogDirectory
    覆盖本次运行日志目录；默认写入 `ai/skills/logs`。
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$ConfigPath = '',

    [Alias('Agents')]
    [string[]]$Agent = @(),

    [Alias('SkillName')]
    [string[]]$Name = @(),

    [switch]$IncludeDevAll,

    [switch]$DryRun,

    [switch]$Yes,

    [switch]$Force,

    [string]$LogDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SkillsInstallerRoot = $PSScriptRoot
$script:SkillsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:SkillsInstallerRoot '..' '..'))
$script:SkillsConfigModuleLoaded = $false

function ConvertTo-SkillsHashtable {
    <#
    .SYNOPSIS
        将配置节点转换为 hashtable。

    .DESCRIPTION
        JSON 配置经过共享解析器读取后，嵌套对象仍可能是 PSCustomObject。
        此函数只做业务层需要的浅层转换，避免直接操作对象属性导致大小写或类型漂移。

    .PARAMETER InputObject
        待转换的配置对象；传入空值时返回空表。

    .OUTPUTS
        hashtable。转换后的浅层键值表。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        return @{} + $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }
        return $result
    }

    $objectResult = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $objectResult[$property.Name] = $property.Value
    }
    return $objectResult
}

function Get-SkillsConfigValue {
    <#
    .SYNOPSIS
        按大小写不敏感方式读取配置值。

    .PARAMETER Values
        配置键值表。

    .PARAMETER Name
        要读取的键名。

    .PARAMETER DefaultValue
        未命中时返回的默认值。

    .OUTPUTS
        object。命中的值或默认值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Values,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$DefaultValue = $null
    )

    foreach ($entry in $Values.GetEnumerator()) {
        if ([string]::Equals([string]$entry.Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry.Value
        }
    }

    return $DefaultValue
}

function ConvertTo-SkillsStringArray {
    <#
    .SYNOPSIS
        将配置值转换为字符串数组。

    .DESCRIPTION
        支持 JSON 数组、PowerShell 数组、逗号分隔字符串与单个标量值。
        空字符串会被过滤，保证后续命令参数不会出现空项。

    .PARAMETER Value
        待转换的配置值。

    .OUTPUTS
        string[]。规范化后的字符串数组。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    $items = if ($Value -is [string]) {
        $Value -split ','
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [hashtable]) {
        @($Value)
    }
    else {
        @($Value)
    }

    return [string[]]@($items | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

function Import-SkillsConfigModule {
    <#
    .SYNOPSIS
        加载仓库共享配置解析模块。

    .DESCRIPTION
        通过 `psutils/modules/config.psm1` 复用 `psutils/src/config` 的 JSON 配置读取逻辑，
        让脚本只负责声明来源和业务校验。

    .OUTPUTS
        None。模块加载到当前会话。
    #>
    [CmdletBinding()]
    param()

    if ($script:SkillsConfigModuleLoaded) {
        return
    }

    $configModulePath = Join-Path $script:SkillsRepoRoot 'psutils/modules/config.psm1'
    if (-not (Test-Path -LiteralPath $configModulePath -PathType Leaf)) {
        throw "未找到共享配置解析器模块: $configModulePath"
    }

    Import-Module $configModulePath -Force
    $script:SkillsConfigModuleLoaded = $true
}

function Resolve-SkillsDefaultConfigPath {
    <#
    .SYNOPSIS
        解析默认 skills 配置文件路径。

    .OUTPUTS
        string。默认配置文件绝对路径。
    #>
    [CmdletBinding()]
    param()

    return (Join-Path $script:SkillsInstallerRoot 'skills.config.json')
}

function Resolve-SkillsDefaultLogDirectory {
    <#
    .SYNOPSIS
        解析默认日志目录。

    .OUTPUTS
        string。默认日志目录绝对路径。
    #>
    [CmdletBinding()]
    param()

    return (Join-Path $script:SkillsInstallerRoot 'logs')
}

function Resolve-SkillsEnvPlaceholder {
    <#
    .SYNOPSIS
        展开路径中的环境变量占位符。

    .DESCRIPTION
        支持 `${NAME}` 与平台原生 `%NAME%` 形式。`${NAME}` 缺失时抛错，
        防止本地 skill 路径意外解析到错误位置。

    .PARAMETER Value
        原始路径字符串。

    .PARAMETER Context
        当前配置位置，用于错误提示。

    .OUTPUTS
        string。展开后的路径文本。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $pattern = '\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    foreach ($match in [regex]::Matches($Value, $pattern)) {
        $envName = $match.Groups[1].Value
        if ($null -eq [Environment]::GetEnvironmentVariable($envName, 'Process')) {
            throw "环境变量未设置: $envName（$Context）"
        }
    }

    $resolved = [regex]::Replace($Value, $pattern, {
            param($Match)
            $envName = $Match.Groups[1].Value
            return [Environment]::GetEnvironmentVariable($envName, 'Process')
        })

    return [Environment]::ExpandEnvironmentVariables($resolved)
}

function Resolve-SkillsPath {
    <#
    .SYNOPSIS
        将配置中的路径解析为绝对路径。

    .PARAMETER Path
        原始路径配置值。

    .PARAMETER BasePath
        相对路径解析基准目录。

    .PARAMETER Context
        当前配置位置，用于错误提示。

    .OUTPUTS
        string。解析后的绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "路径配置不能为空: $Context"
    }

    $expanded = Resolve-SkillsEnvPlaceholder -Value $Path.Trim() -Context $Context
    if ($expanded -eq '~' -or $expanded.StartsWith('~/') -or $expanded.StartsWith('~\')) {
        $home = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if ([string]::IsNullOrWhiteSpace($home)) {
            throw "无法解析用户主目录: $Context"
        }

        $expanded = if ($expanded -eq '~') { $home } else { Join-Path $home $expanded.Substring(2) }
    }

    $combined = if ([System.IO.Path]::IsPathRooted($expanded)) {
        $expanded
    }
    else {
        Join-Path $BasePath $expanded
    }

    return [System.IO.Path]::GetFullPath($combined)
}

function Resolve-SkillsProjectRoot {
    <#
    .SYNOPSIS
        解析 project scope 的目标项目根目录。

    .DESCRIPTION
        显式 `projectPath` 优先；未配置时优先使用当前仓库根目录，
        若仓库根不可用则尝试 `git rev-parse --show-toplevel`。

    .PARAMETER ProjectPath
        可选项目路径配置值。

    .PARAMETER BasePath
        相对项目路径解析基准目录。

    .OUTPUTS
        string。项目根目录绝对路径。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ProjectPath = '',

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        $resolved = Resolve-SkillsPath -Path $ProjectPath -BasePath $BasePath -Context 'projectPath'
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "projectPath 不存在或不是目录: $resolved"
        }
        return $resolved
    }

    if (Test-Path -LiteralPath (Join-Path $script:SkillsRepoRoot '.git')) {
        return $script:SkillsRepoRoot
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitRoot = & $gitCommand.Source -C $BasePath rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return [System.IO.Path]::GetFullPath($gitRoot.Trim())
        }
    }

    throw '无法解析 project scope 的项目根目录，请在配置中显式设置 projectPath。'
}

function Read-SkillsInstallerConfig {
    <#
    .SYNOPSIS
        读取 skills 安装器配置。

    .DESCRIPTION
        使用共享 `Resolve-ConfigSources` 合并默认值、JSON 文件与 CLI 覆盖参数。
        配置文件必须是 JSON，业务字段校验由后续计划生成函数负责。

    .PARAMETER ConfigPath
        JSON 配置文件路径。

    .PARAMETER CliParameters
        CLI 覆盖参数，主要用于覆盖默认 agent。

    .OUTPUTS
        PSCustomObject。包含 Values、BasePath 与 Path。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ConfigPath,

        [hashtable]$CliParameters = @{}
    )

    $effectivePath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Resolve-SkillsDefaultConfigPath } else { $ConfigPath }
    if ($effectivePath -notmatch '\.json$') {
        throw 'skills 安装配置仅支持 JSON 文件。'
    }

    Import-SkillsConfigModule
    $resolvedPath = [System.IO.Path]::GetFullPath($effectivePath)
    $basePath = Split-Path -Parent $resolvedPath
    $sources = New-Object 'System.Collections.Generic.List[hashtable]'
    $sources.Add(@{
            Type = 'Hashtable'
            Name = 'Defaults'
            Data = @{
                version = 1
                scope   = 'global'
                agents  = @('claude', 'codex')
            }
        }) | Out-Null
    $sources.Add(@{
            Type = 'JsonFile'
            Name = 'ConfigFile'
            Path = $resolvedPath
        }) | Out-Null

    if ($CliParameters.Count -gt 0) {
        $sources.Add(@{
                Type        = 'CliParameters'
                Name        = 'Cli'
                Data        = $CliParameters
                ExcludeKeys = @('ConfigPath', 'Name', 'IncludeDevAll', 'DryRun', 'Yes', 'Force', 'LogDirectory')
            }) | Out-Null
    }

    $resolved = Resolve-ConfigSources -Sources $sources.ToArray() -BasePath $basePath -ErrorOnMissing
    return [pscustomobject]@{
        Values   = $resolved.Values
        BasePath = $basePath
        Path     = $resolvedPath
    }
}

function ConvertTo-SkillsCliAgent {
    <#
    .SYNOPSIS
        将友好 agent 名称映射为 skills CLI 名称。

    .PARAMETER Agent
        配置或 CLI 中的 agent 名称。

    .OUTPUTS
        string。传递给 `skills --agent` 的名称。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Agent
    )

    switch ($Agent.Trim().ToLowerInvariant()) {
        'claude' { return 'claude-code' }
        'claude-code' { return 'claude-code' }
        'codex' { return 'codex' }
        default { return $Agent.Trim() }
    }
}

function Resolve-SkillsAgents {
    <#
    .SYNOPSIS
        解析某个安装项最终使用的 agent 列表。

    .PARAMETER ConfigValues
        顶层配置值。

    .PARAMETER Item
        单个 skill 或 tool 配置。

    .PARAMETER OverrideAgents
        CLI 参数传入的统一 agent 覆盖列表。

    .OUTPUTS
        string[]。去重并映射后的 skills CLI agent 名称。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigValues,

        [hashtable]$Item = @{},

        [string[]]$OverrideAgents = @()
    )

    $rawAgents = if (@($OverrideAgents).Count -gt 0) {
        $OverrideAgents
    }
    else {
        $itemAgents = @(ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $Item -Name 'agents'))
        if (@($itemAgents).Count -gt 0) {
            $itemAgents
        }
        else {
            @(ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $ConfigValues -Name 'agents' -DefaultValue @('claude', 'codex')))
        }
    }

    if (@($rawAgents).Count -eq 0) {
        throw 'agent 列表不能为空。'
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $agents = New-Object 'System.Collections.Generic.List[string]'
    foreach ($agentName in $rawAgents) {
        $mapped = ConvertTo-SkillsCliAgent -Agent $agentName
        if (-not [string]::IsNullOrWhiteSpace($mapped) -and $seen.Add($mapped)) {
            $agents.Add($mapped) | Out-Null
        }
    }

    return [string[]]$agents.ToArray()
}

function Resolve-SkillsScope {
    <#
    .SYNOPSIS
        解析安装项作用域。

    .PARAMETER ConfigValues
        顶层配置值。

    .PARAMETER Item
        单个 skill 配置。

    .OUTPUTS
        string。返回 `global` 或 `project`。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigValues,

        [hashtable]$Item = @{}
    )

    $scope = [string](Get-SkillsConfigValue -Values $Item -Name 'scope' -DefaultValue (Get-SkillsConfigValue -Values $ConfigValues -Name 'scope' -DefaultValue 'global'))
    $scope = $scope.Trim().ToLowerInvariant()
    if ($scope -notin @('global', 'project')) {
        throw "不支持的 scope: $scope"
    }

    return $scope
}

function Test-SkillsLocalSource {
    <#
    .SYNOPSIS
        判断 skill 来源是否是本地路径。

    .PARAMETER Source
        skill 来源字符串。

    .PARAMETER SourceType
        可选来源类型。

    .OUTPUTS
        bool。本地路径返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [AllowEmptyString()]
        [string]$SourceType = ''
    )

    if ([string]::Equals($SourceType, 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return [System.IO.Path]::IsPathRooted($Source) -or $Source.StartsWith('./') -or $Source.StartsWith('../') -or $Source.StartsWith('.\') -or $Source.StartsWith('..\')
}

function Resolve-SkillsSource {
    <#
    .SYNOPSIS
        解析 skill 安装来源。

    .PARAMETER SkillName
        skill 配置键名。

    .PARAMETER Item
        单个 skill 配置。

    .PARAMETER BasePath
        相对路径解析基准目录。

    .OUTPUTS
        PSCustomObject。包含 Source、SourceType 与 IsLocal。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SkillName,

        [Parameter(Mandatory)]
        [hashtable]$Item,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $source = [string](Get-SkillsConfigValue -Values $Item -Name 'source')
    if ([string]::IsNullOrWhiteSpace($source)) {
        throw "skill '$SkillName' 缺少 source。"
    }

    $sourceType = [string](Get-SkillsConfigValue -Values $Item -Name 'sourceType' -DefaultValue '')
    $isLocal = Test-SkillsLocalSource -Source $source -SourceType $sourceType
    $resolvedSource = if ($isLocal) {
        $localPath = Resolve-SkillsPath -Path $source -BasePath $BasePath -Context "$SkillName.source"
        $skillFile = Join-Path $localPath 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            throw "本地 skill 缺少 SKILL.md: $localPath"
        }
        $localPath
    }
    else {
        $source.Trim()
    }

    return [pscustomobject]@{
        Source     = $resolvedSource
        SourceType = if ([string]::IsNullOrWhiteSpace($sourceType)) { if ($isLocal) { 'local' } else { 'github' } } else { $sourceType }
        IsLocal    = $isLocal
    }
}

function New-SkillsAddArguments {
    <#
    .SYNOPSIS
        生成 `npx skills add` 参数。

    .PARAMETER PlanItem
        单个 skill 安装计划项。

    .PARAMETER AssumeYes
        是否向 skills CLI 传递 `--yes`。

    .OUTPUTS
        string[]。传递给 `npx` 的参数数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$PlanItem,

        [switch]$AssumeYes
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @('skills', 'add', [string]$PlanItem.Source)) {
        $arguments.Add($value) | Out-Null
    }

    if ($PlanItem.Scope -eq 'global') {
        $arguments.Add('--global') | Out-Null
    }

    if (@($PlanItem.SkillSelectors).Count -gt 0) {
        $arguments.Add('--skill') | Out-Null
        foreach ($selector in $PlanItem.SkillSelectors) {
            $arguments.Add([string]$selector) | Out-Null
        }
    }

    if (@($PlanItem.Agents).Count -gt 0) {
        $arguments.Add('--agent') | Out-Null
        foreach ($agentName in $PlanItem.Agents) {
            $arguments.Add([string]$agentName) | Out-Null
        }
    }

    if ($PlanItem.Copy) {
        $arguments.Add('--copy') | Out-Null
    }

    if ($AssumeYes) {
        $arguments.Add('--yes') | Out-Null
    }

    return [string[]]$arguments.ToArray()
}

function ConvertTo-SkillsCommandPlan {
    <#
    .SYNOPSIS
        将配置中的附带命令转换为执行计划。

    .PARAMETER OwnerName
        命令所属 skill 或 tool 名称。

    .PARAMETER Commands
        原始命令配置集合。

    .PARAMETER DefaultPhase
        未声明 phase 时使用的默认阶段。

    .PARAMETER BasePath
        相对工作目录解析基准目录。

    .OUTPUTS
        PSCustomObject[]。规范化后的命令计划。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OwnerName,

        [AllowNull()]
        [object]$Commands,

        [ValidateSet('preInstall', 'postInstall')]
        [string]$DefaultPhase = 'postInstall',

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    if ($null -eq $Commands) {
        return @()
    }

    $items = if ($Commands -is [string]) { @(@{ command = $Commands }) } else { @($Commands) }
    $plans = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($rawCommand in $items) {
        $index += 1
        $commandConfig = if ($rawCommand -is [string]) { @{ command = $rawCommand } } else { ConvertTo-SkillsHashtable -InputObject $rawCommand }
        $command = [string](Get-SkillsConfigValue -Values $commandConfig -Name 'command')
        if ([string]::IsNullOrWhiteSpace($command)) {
            throw "$OwnerName.commands[$index] 缺少 command。"
        }

        $phase = [string](Get-SkillsConfigValue -Values $commandConfig -Name 'phase' -DefaultValue $DefaultPhase)
        if ($phase -notin @('preInstall', 'postInstall')) {
            throw "$OwnerName.commands[$index] phase 只支持 preInstall 或 postInstall。"
        }

        $workingDirectoryValue = [string](Get-SkillsConfigValue -Values $commandConfig -Name 'workingDirectory' -DefaultValue '')
        $workingDirectory = if ([string]::IsNullOrWhiteSpace($workingDirectoryValue)) {
            $BasePath
        }
        else {
            Resolve-SkillsPath -Path $workingDirectoryValue -BasePath $BasePath -Context "$OwnerName.commands[$index].workingDirectory"
        }

        $plans.Add([pscustomobject]@{
                Type             = 'Command'
                Owner            = $OwnerName
                Name             = [string](Get-SkillsConfigValue -Values $commandConfig -Name 'name' -DefaultValue "$OwnerName-command-$index")
                Phase            = $phase
                Command          = $command.Trim()
                Arguments        = ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $commandConfig -Name 'args')
                WorkingDirectory = $workingDirectory
            }) | Out-Null
    }

    return [pscustomobject[]]$plans.ToArray()
}

function New-SkillsPlanFromConfig {
    <#
    .SYNOPSIS
        根据配置生成完整安装计划。

    .PARAMETER Config
        `Read-SkillsInstallerConfig` 返回的配置对象。

    .PARAMETER OverrideAgents
        CLI 传入的统一 agent 覆盖列表。

    .PARAMETER Name
        可选名称筛选。

    .PARAMETER IncludeDevAll
        是否自动纳入 dev 目录下所有本地 skill。

    .OUTPUTS
        PSCustomObject。包含 Tools、Skills、Commands 与 Steps。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [string[]]$OverrideAgents = @(),

        [string[]]$Name = @(),

        [switch]$IncludeDevAll
    )

    $values = ConvertTo-SkillsHashtable -InputObject $Config.Values
    $selectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($itemName in $Name) {
        if (-not [string]::IsNullOrWhiteSpace($itemName)) {
            $selectedNames.Add($itemName.Trim()) | Out-Null
        }
    }

    $skillConfigs = ConvertTo-SkillsHashtable -InputObject (Get-SkillsConfigValue -Values $values -Name 'skills' -DefaultValue @{})
    if ($IncludeDevAll) {
        $devRoot = Join-Path $script:SkillsInstallerRoot 'dev'
        if (Test-Path -LiteralPath $devRoot -PathType Container) {
            foreach ($skillDir in Get-ChildItem -LiteralPath $devRoot -Directory) {
                $skillFile = Join-Path $skillDir.FullName 'SKILL.md'
                if ((Test-Path -LiteralPath $skillFile -PathType Leaf) -and -not $skillConfigs.ContainsKey($skillDir.Name)) {
                    $skillConfigs[$skillDir.Name] = @{
                        description = "本地开发 skill: $($skillDir.Name)"
                        source      = "./dev/$($skillDir.Name)"
                        sourceType  = 'local'
                    }
                }
            }
        }
    }

    $toolPlans = New-Object 'System.Collections.Generic.List[object]'
    $skillPlans = New-Object 'System.Collections.Generic.List[object]'
    $commandPlans = New-Object 'System.Collections.Generic.List[object]'
    $steps = New-Object 'System.Collections.Generic.List[object]'

    $tools = ConvertTo-SkillsHashtable -InputObject (Get-SkillsConfigValue -Values $values -Name 'tools' -DefaultValue @{})
    foreach ($toolEntry in $tools.GetEnumerator() | Sort-Object Name) {
        $toolName = [string]$toolEntry.Key
        if ($selectedNames.Count -gt 0 -and -not $selectedNames.Contains($toolName)) {
            continue
        }

        $tool = ConvertTo-SkillsHashtable -InputObject $toolEntry.Value
        $toolCommand = [string](Get-SkillsConfigValue -Values $tool -Name 'command')
        if ([string]::IsNullOrWhiteSpace($toolCommand)) {
            throw "tool '$toolName' 缺少 command。"
        }

        $check = ConvertTo-SkillsHashtable -InputObject (Get-SkillsConfigValue -Values $tool -Name 'check' -DefaultValue @{})
        $phase = [string](Get-SkillsConfigValue -Values $tool -Name 'phase' -DefaultValue 'preInstall')
        if ($phase -notin @('preInstall', 'postInstall')) {
            throw "tool '$toolName' phase 只支持 preInstall 或 postInstall。"
        }

        $workingDirectoryValue = [string](Get-SkillsConfigValue -Values $tool -Name 'workingDirectory' -DefaultValue '')
        $workingDirectory = if ([string]::IsNullOrWhiteSpace($workingDirectoryValue)) {
            $Config.BasePath
        }
        else {
            Resolve-SkillsPath -Path $workingDirectoryValue -BasePath $Config.BasePath -Context "$toolName.workingDirectory"
        }

        $toolPlan = [pscustomobject]@{
            Type             = 'Tool'
            Name             = $toolName
            Description      = [string](Get-SkillsConfigValue -Values $tool -Name 'description' -DefaultValue '')
            Phase            = $phase
            Command          = $toolCommand.Trim()
            Arguments        = ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $tool -Name 'args')
            WorkingDirectory = $workingDirectory
            Check            = if ($check.Count -gt 0) { $check } else { $null }
        }
        $toolPlans.Add($toolPlan) | Out-Null
        $steps.Add($toolPlan) | Out-Null
    }

    foreach ($skillEntry in $skillConfigs.GetEnumerator() | Sort-Object Name) {
        $skillName = [string]$skillEntry.Key
        if ($selectedNames.Count -gt 0 -and -not $selectedNames.Contains($skillName)) {
            continue
        }

        $skill = ConvertTo-SkillsHashtable -InputObject $skillEntry.Value
        $scope = Resolve-SkillsScope -ConfigValues $values -Item $skill
        $projectPath = if ($scope -eq 'project') {
            $itemProjectPath = [string](Get-SkillsConfigValue -Values $skill -Name 'projectPath' -DefaultValue (Get-SkillsConfigValue -Values $values -Name 'projectPath' -DefaultValue ''))
            Resolve-SkillsProjectRoot -ProjectPath $itemProjectPath -BasePath $Config.BasePath
        }
        else {
            ''
        }

        $sourceInfo = Resolve-SkillsSource -SkillName $skillName -Item $skill -BasePath $Config.BasePath
        $agents = Resolve-SkillsAgents -ConfigValues $values -Item $skill -OverrideAgents $OverrideAgents
        $selectorOverride = @(ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $skill -Name 'skill'))
        $skillSelectors = if (@($selectorOverride).Count -gt 0) {
            $selectorOverride
        }
        elseif ($sourceInfo.IsLocal) {
            @()
        }
        else {
            @($skillName)
        }

        $copyValue = Get-SkillsConfigValue -Values $skill -Name 'copy' -DefaultValue $false
        $allCommands = @(ConvertTo-SkillsCommandPlan -OwnerName $skillName -Commands (Get-SkillsConfigValue -Values $skill -Name 'commands') -BasePath $Config.BasePath)
        $preCommands = @($allCommands | Where-Object { $_.Phase -eq 'preInstall' })
        $postCommands = @($allCommands | Where-Object { $_.Phase -eq 'postInstall' })
        foreach ($commandPlan in @($preCommands) + @($postCommands)) {
            $commandPlans.Add($commandPlan) | Out-Null
        }

        $skillPlan = [pscustomobject]@{
            Type             = 'Skill'
            Name             = $skillName
            Description      = [string](Get-SkillsConfigValue -Values $skill -Name 'description' -DefaultValue '')
            Source           = $sourceInfo.Source
            SourceType       = $sourceInfo.SourceType
            Scope            = $scope
            ProjectPath      = $projectPath
            Agents           = [string[]]$agents
            SkillSelectors   = [string[]]@($skillSelectors)
            Copy             = [bool]$copyValue
            WorkingDirectory = if ($scope -eq 'project') { $projectPath } else { $Config.BasePath }
            Arguments        = @()
            PreCommands      = [pscustomobject[]]$preCommands
            PostCommands     = [pscustomobject[]]$postCommands
        }
        $skillPlan.Arguments = New-SkillsAddArguments -PlanItem $skillPlan -AssumeYes
        foreach ($preCommand in $skillPlan.PreCommands) {
            $steps.Add($preCommand) | Out-Null
        }
        $skillPlans.Add($skillPlan) | Out-Null
        $steps.Add($skillPlan) | Out-Null
        foreach ($postCommand in $skillPlan.PostCommands) {
            $steps.Add($postCommand) | Out-Null
        }
    }

    if ($selectedNames.Count -gt 0 -and $toolPlans.Count -eq 0 -and $skillPlans.Count -eq 0) {
        throw "未找到指定 skill/tool: $($Name -join ', ')"
    }

    return [pscustomobject]@{
        Tools    = [pscustomobject[]]$toolPlans.ToArray()
        Skills   = [pscustomobject[]]$skillPlans.ToArray()
        Commands = [pscustomobject[]]$commandPlans.ToArray()
        Steps    = [pscustomobject[]]$steps.ToArray()
    }
}

function Format-SkillsCommandLine {
    <#
    .SYNOPSIS
        格式化外部命令用于展示和日志。

    .PARAMETER Command
        命令名或路径。

    .PARAMETER Arguments
        参数数组。

    .OUTPUTS
        string。可读命令行文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    $parts = @($Command) + @($Arguments)
    return ($parts | ForEach-Object {
            $value = [string]$_
            if ($value -match '\s' -or $value -match '["'']') {
                '"' + ($value -replace '"', '\"') + '"'
            }
            else {
                $value
            }
        }) -join ' '
}

function Resolve-SkillsExecutablePath {
    <#
    .SYNOPSIS
        解析外部命令为可执行路径。

    .DESCRIPTION
        `System.Diagnostics.ProcessStartInfo` 不会像 PowerShell 一样自动处理函数、
        alias 或脚本包装器。这里优先选择 Application 类型，避免 Windows 上误选
        `npx.ps1` 这类需要 PowerShell 承载的脚本文件。

    .PARAMETER Command
        命令名或可执行文件路径。

    .OUTPUTS
        string。可传给 ProcessStartInfo.FileName 的路径或命令名。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    if ([System.IO.Path]::IsPathRooted($Command)) {
        return $Command
    }

    $commands = @(Get-Command -Name $Command -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        return $Command
    }

    $application = $commands | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($application) {
        return $application.Source
    }

    $externalScript = $commands | Where-Object { $_.CommandType -eq 'ExternalScript' } | Select-Object -First 1
    if ($externalScript) {
        return $externalScript.Source
    }

    return $commands[0].Source
}

function Show-SkillsInstallPlan {
    <#
    .SYNOPSIS
        输出安装计划预览。

    .PARAMETER Plan
        `New-SkillsPlanFromConfig` 返回的计划对象。

    .OUTPUTS
        None。向控制台输出计划。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan
    )

    if ($Plan.Tools.Count -gt 0) {
        Write-Host 'Tool setup:'
        foreach ($tool in $Plan.Tools) {
            $checkText = if ($null -ne $tool.Check) { 'check: yes' } else { 'check: no' }
            Write-Host ("- {0} [{1}] {2}" -f $tool.Name, $tool.Phase, $checkText)
            if (-not [string]::IsNullOrWhiteSpace($tool.Description)) {
                Write-Host ("  {0}" -f $tool.Description)
            }
            Write-Host ("  {0}" -f (Format-SkillsCommandLine -Command $tool.Command -Arguments $tool.Arguments))
        }
    }

    if ($Plan.Skills.Count -gt 0) {
        Write-Host 'Skill install:'
        foreach ($skill in $Plan.Skills) {
            $target = if ($skill.Scope -eq 'project') { $skill.ProjectPath } else { 'global' }
            Write-Host ("- {0} [{1}] -> {2}" -f $skill.Name, ($skill.Agents -join ', '), $target)
            if (-not [string]::IsNullOrWhiteSpace($skill.Description)) {
                Write-Host ("  {0}" -f $skill.Description)
            }
            Write-Host ("  {0}" -f (Format-SkillsCommandLine -Command 'npx' -Arguments $skill.Arguments))
        }
    }

    if ($Plan.Steps.Count -eq 0) {
        Write-Host '没有需要执行的安装项。'
    }
}

function Confirm-SkillsInstallPlan {
    <#
    .SYNOPSIS
        确认是否继续执行安装计划。

    .PARAMETER Plan
        已生成的安装计划。

    .PARAMETER Yes
        为真时跳过交互确认。

    .OUTPUTS
        bool。允许继续时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [switch]$Yes
    )

    if ($Yes) {
        return $true
    }

    if ($Plan.Steps.Count -eq 0) {
        return $false
    }

    $answer = Read-Host '继续执行以上安装计划？输入 y 确认'
    return $answer -in @('y', 'Y', 'yes', 'YES')
}

function New-SkillsLogFile {
    <#
    .SYNOPSIS
        创建本次安装日志文件。

    .PARAMETER LogDirectory
        日志目录路径。

    .OUTPUTS
        string。日志文件绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory
    )

    $resolvedDirectory = [System.IO.Path]::GetFullPath($LogDirectory)
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $resolvedDirectory "skills-install-$timestamp.log"
    Set-Content -LiteralPath $logPath -Encoding utf8NoBOM -Value "skills install log $timestamp"
    return $logPath
}

function Write-SkillsLogLine {
    <#
    .SYNOPSIS
        写入单行安装日志。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER Message
        日志消息。

    .OUTPUTS
        None。追加日志内容。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Encoding utf8NoBOM -Value $line
}

function Invoke-SkillsExternalCommand {
    <#
    .SYNOPSIS
        执行外部命令并记录 stdout、stderr 与退出码。

    .PARAMETER Command
        命令名或可执行文件路径。

    .PARAMETER Arguments
        参数数组。

    .PARAMETER WorkingDirectory
        命令工作目录。

    .PARAMETER LogPath
        可选日志文件路径。

    .PARAMETER AllowFailure
        为真时命令非零退出也返回结果，不抛异常。

    .OUTPUTS
        PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @(),

        [string]$WorkingDirectory = (Get-Location).Path,

        [AllowEmptyString()]
        [string]$LogPath = '',

        [switch]$AllowFailure
    )

    $commandLine = Format-SkillsCommandLine -Command $Command -Arguments $Arguments
    Write-SkillsLogLine -LogPath $LogPath -Message "COMMAND $commandLine"
    Write-SkillsLogLine -LogPath $LogPath -Message "CWD $WorkingDirectory"

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Resolve-SkillsExecutablePath -Command $Command
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
    }
    finally {
        $process.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        [Console]::Out.Write($stdout)
        Write-SkillsLogLine -LogPath $LogPath -Message "STDOUT $($stdout.TrimEnd())"
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        [Console]::Error.Write($stderr)
        Write-SkillsLogLine -LogPath $LogPath -Message "STDERR $($stderr.TrimEnd())"
    }

    Write-SkillsLogLine -LogPath $LogPath -Message "EXIT $($process.ExitCode)"
    $result = [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }

    if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "外部命令执行失败($($process.ExitCode)): $commandLine"
    }

    return $result
}

function Test-SkillsToolCheckResult {
    <#
    .SYNOPSIS
        判断 tool check 命令结果是否表示已安装。

    .PARAMETER Check
        tool check 配置。

    .PARAMETER Result
        外部命令结果对象。

    .OUTPUTS
        bool。check 满足时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Check,

        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    $exitCodes = ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $Check -Name 'exitCodes' -DefaultValue @('0')) |
        ForEach-Object { [int]$_ }
    if ($Result.ExitCode -notin $exitCodes) {
        return $false
    }

    $combinedOutput = "{0}`n{1}" -f $Result.StdOut, $Result.StdErr
    $contains = [string](Get-SkillsConfigValue -Values $Check -Name 'contains' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($contains)) {
        return $combinedOutput.IndexOf($contains, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    $regex = [string](Get-SkillsConfigValue -Values $Check -Name 'regex' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($regex)) {
        return [regex]::IsMatch($combinedOutput, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    return $true
}

function Invoke-SkillsToolStep {
    <#
    .SYNOPSIS
        执行单个 tool setup 步骤。

    .PARAMETER Tool
        tool 安装计划项。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .OUTPUTS
        None。失败时抛出异常。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Tool,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner
    )

    if (-not $WhatIfPreference -and $null -ne $Tool.Check) {
        $check = ConvertTo-SkillsHashtable -InputObject $Tool.Check
        $checkCommand = [string](Get-SkillsConfigValue -Values $check -Name 'command')
        if ([string]::IsNullOrWhiteSpace($checkCommand)) {
            throw "tool '$($Tool.Name)' check 缺少 command。"
        }

        $checkArguments = ConvertTo-SkillsStringArray -Value (Get-SkillsConfigValue -Values $check -Name 'args')
        $checkResult = & $CommandRunner $checkCommand $checkArguments $Tool.WorkingDirectory $LogPath $true
        if (Test-SkillsToolCheckResult -Check $check -Result $checkResult) {
            Write-Host "tool '$($Tool.Name)' 已配置，跳过 setup。"
            Write-SkillsLogLine -LogPath $LogPath -Message "SKIP tool $($Tool.Name)"
            return
        }
    }

    $target = "tool:$($Tool.Name)"
    $action = Format-SkillsCommandLine -Command $Tool.Command -Arguments $Tool.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner $Tool.Command $Tool.Arguments $Tool.WorkingDirectory $LogPath $false | Out-Null
    }
}

function Invoke-SkillsCommandStep {
    <#
    .SYNOPSIS
        执行 skill 附带命令。

    .PARAMETER CommandPlan
        附带命令计划项。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .OUTPUTS
        None。失败时抛出异常。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$CommandPlan,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner
    )

    $target = "command:$($CommandPlan.Owner)/$($CommandPlan.Name)"
    $action = Format-SkillsCommandLine -Command $CommandPlan.Command -Arguments $CommandPlan.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner $CommandPlan.Command $CommandPlan.Arguments $CommandPlan.WorkingDirectory $LogPath $false | Out-Null
    }
}

function Invoke-SkillsInstallStep {
    <#
    .SYNOPSIS
        执行单个 `skills add` 安装步骤。

    .PARAMETER Skill
        skill 安装计划项。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .PARAMETER Force
        表示用户明确选择继续执行安装命令。

    .OUTPUTS
        None。失败时抛出异常。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Skill,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner,

        [switch]$Force
    )

    if ($Force) {
        Write-SkillsLogLine -LogPath $LogPath -Message "FORCE skill $($Skill.Name)"
    }

    $target = "skill:$($Skill.Name)"
    $action = Format-SkillsCommandLine -Command 'npx' -Arguments $Skill.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner 'npx' $Skill.Arguments $Skill.WorkingDirectory $LogPath $false | Out-Null
    }
}

function Invoke-SkillsInstallPlan {
    <#
    .SYNOPSIS
        按顺序执行安装计划。

    .PARAMETER Plan
        完整安装计划。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .PARAMETER Force
        表示用户明确选择继续执行安装命令。

    .OUTPUTS
        None。失败时抛出异常。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner,

        [switch]$Force
    )

    foreach ($step in $Plan.Steps) {
        switch ($step.Type) {
            'Tool' {
                Invoke-SkillsToolStep -Tool $step -LogPath $LogPath -CommandRunner $CommandRunner
            }
            'Command' {
                Invoke-SkillsCommandStep -CommandPlan $step -LogPath $LogPath -CommandRunner $CommandRunner
            }
            'Skill' {
                Invoke-SkillsInstallStep -Skill $step -LogPath $LogPath -CommandRunner $CommandRunner -Force:$Force
            }
            default {
                throw "未知安装步骤类型: $($step.Type)"
            }
        }
    }
}

function Invoke-SkillsInstallMain {
    <#
    .SYNOPSIS
        skills 安装器主入口。

    .PARAMETER ConfigPath
        JSON 配置文件路径。

    .PARAMETER Agent
        CLI 传入的 agent 覆盖列表。

    .PARAMETER Name
        只处理指定 skill 或 tool 名称。

    .PARAMETER IncludeDevAll
        是否自动发现 dev 目录下全部本地 skill。

    .PARAMETER DryRun
        是否只展示计划。

    .PARAMETER Yes
        是否跳过计划确认。

    .PARAMETER Force
        是否明确继续执行安装命令。

    .PARAMETER LogDirectory
        日志目录。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .OUTPUTS
        int。进程退出码。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [AllowEmptyString()]
        [string]$ConfigPath = '',

        [string[]]$Agent = @(),

        [string[]]$Name = @(),

        [switch]$IncludeDevAll,

        [switch]$DryRun,

        [switch]$Yes,

        [switch]$Force,

        [AllowEmptyString()]
        [string]$LogDirectory = '',

        [scriptblock]$CommandRunner = {
            param(
                [string]$Command,
                [string[]]$Arguments,
                [string]$WorkingDirectory,
                [string]$LogPath,
                [bool]$AllowFailure
            )
            Invoke-SkillsExternalCommand -Command $Command -Arguments $Arguments -WorkingDirectory $WorkingDirectory -LogPath $LogPath -AllowFailure:$AllowFailure
        }
    )

    $cliParameters = @{}
    if ($Agent.Count -gt 0) {
        $cliParameters['Agent'] = $Agent
    }

    $config = Read-SkillsInstallerConfig -ConfigPath $ConfigPath -CliParameters $cliParameters
    $plan = New-SkillsPlanFromConfig -Config $config -OverrideAgents $Agent -Name $Name -IncludeDevAll:$IncludeDevAll
    Show-SkillsInstallPlan -Plan $plan

    if ($DryRun) {
        return 0
    }

    if ($WhatIfPreference) {
        Invoke-SkillsInstallPlan -Plan $plan -LogPath '' -CommandRunner $CommandRunner -Force:$Force
        return 0
    }

    if (-not (Confirm-SkillsInstallPlan -Plan $plan -Yes:$Yes)) {
        Write-Host '已取消。'
        return 0
    }

    $effectiveLogDirectory = if ([string]::IsNullOrWhiteSpace($LogDirectory)) { Resolve-SkillsDefaultLogDirectory } else { $LogDirectory }
    $logPath = New-SkillsLogFile -LogDirectory $effectiveLogDirectory
    Write-Host "日志: $logPath"
    Write-SkillsLogLine -LogPath $logPath -Message "CONFIG $($config.Path)"
    Write-SkillsLogLine -LogPath $logPath -Message "FORCE $([bool]$Force)"

    Invoke-SkillsInstallPlan -Plan $plan -LogPath $logPath -CommandRunner $CommandRunner -Force:$Force
    return 0
}

if ($env:SKILLS_INSTALLER_SKIP_MAIN -ne '1') {
    try {
        exit (Invoke-SkillsInstallMain `
                -ConfigPath $ConfigPath `
                -Agent $Agent `
                -Name $Name `
                -IncludeDevAll:$IncludeDevAll `
                -DryRun:$DryRun `
                -Yes:$Yes `
                -Force:$Force `
                -LogDirectory $LogDirectory)
    }
    catch {
        Write-Error $_
        exit 1
    }
}
