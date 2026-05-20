# skills 安装器私有 helper：配置读取与安装计划生成。
# 此文件由 Install-Skills.ps1 dot-source 加载，不作为独立入口运行。

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
        $resolved = Resolve-ConfigPath -Path $ProjectPath -BasePath $BasePath -Context 'projectPath'
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
        $itemAgents = @(ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Item -Name 'agents'))
        if (@($itemAgents).Count -gt 0) {
            $itemAgents
        }
        else {
            @(ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $ConfigValues -Name 'agents' -DefaultValue @('claude', 'codex')))
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

    $scope = [string](Get-ConfigValue -Values $Item -Name 'scope' -DefaultValue (Get-ConfigValue -Values $ConfigValues -Name 'scope' -DefaultValue 'global'))
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

    $source = [string](Get-ConfigValue -Values $Item -Name 'source')
    if ([string]::IsNullOrWhiteSpace($source)) {
        throw "skill '$SkillName' 缺少 source。"
    }

    $sourceType = [string](Get-ConfigValue -Values $Item -Name 'sourceType' -DefaultValue '')
    $isLocal = Test-SkillsLocalSource -Source $source -SourceType $sourceType
    $resolvedSource = if ($isLocal) {
        $localPath = Resolve-ConfigPath -Path $source -BasePath $BasePath -Context "$SkillName.source"
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
        $commandConfig = if ($rawCommand -is [string]) { @{ command = $rawCommand } } else { ConvertTo-ConfigHashtable -InputObject $rawCommand }
        $command = [string](Get-ConfigValue -Values $commandConfig -Name 'command')
        if ([string]::IsNullOrWhiteSpace($command)) {
            throw "$OwnerName.commands[$index] 缺少 command。"
        }

        $phase = [string](Get-ConfigValue -Values $commandConfig -Name 'phase' -DefaultValue $DefaultPhase)
        if ($phase -notin @('preInstall', 'postInstall')) {
            throw "$OwnerName.commands[$index] phase 只支持 preInstall 或 postInstall。"
        }

        $workingDirectoryValue = [string](Get-ConfigValue -Values $commandConfig -Name 'workingDirectory' -DefaultValue '')
        $workingDirectory = if ([string]::IsNullOrWhiteSpace($workingDirectoryValue)) {
            $BasePath
        }
        else {
            Resolve-ConfigPath -Path $workingDirectoryValue -BasePath $BasePath -Context "$OwnerName.commands[$index].workingDirectory"
        }

        $plans.Add([pscustomobject]@{
                Type             = 'Command'
                Owner            = $OwnerName
                Name             = [string](Get-ConfigValue -Values $commandConfig -Name 'name' -DefaultValue "$OwnerName-command-$index")
                Phase            = $phase
                Command          = $command.Trim()
                Arguments        = ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $commandConfig -Name 'args')
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

    $values = ConvertTo-ConfigHashtable -InputObject $Config.Values
    $selectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($itemName in $Name) {
        if (-not [string]::IsNullOrWhiteSpace($itemName)) {
            $selectedNames.Add($itemName.Trim()) | Out-Null
        }
    }

    $skillConfigs = ConvertTo-ConfigHashtable -InputObject (Get-ConfigValue -Values $values -Name 'skills' -DefaultValue @{})
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

    $tools = ConvertTo-ConfigHashtable -InputObject (Get-ConfigValue -Values $values -Name 'tools' -DefaultValue @{})
    foreach ($toolEntry in $tools.GetEnumerator() | Sort-Object Name) {
        $toolName = [string]$toolEntry.Key
        if ($selectedNames.Count -gt 0 -and -not $selectedNames.Contains($toolName)) {
            continue
        }

        $tool = ConvertTo-ConfigHashtable -InputObject $toolEntry.Value
        $toolCommand = [string](Get-ConfigValue -Values $tool -Name 'command')
        if ([string]::IsNullOrWhiteSpace($toolCommand)) {
            throw "tool '$toolName' 缺少 command。"
        }

        $check = ConvertTo-ConfigHashtable -InputObject (Get-ConfigValue -Values $tool -Name 'check' -DefaultValue @{})
        $phase = [string](Get-ConfigValue -Values $tool -Name 'phase' -DefaultValue 'preInstall')
        if ($phase -notin @('preInstall', 'postInstall')) {
            throw "tool '$toolName' phase 只支持 preInstall 或 postInstall。"
        }

        $workingDirectoryValue = [string](Get-ConfigValue -Values $tool -Name 'workingDirectory' -DefaultValue '')
        $workingDirectory = if ([string]::IsNullOrWhiteSpace($workingDirectoryValue)) {
            $Config.BasePath
        }
        else {
            Resolve-ConfigPath -Path $workingDirectoryValue -BasePath $Config.BasePath -Context "$toolName.workingDirectory"
        }

        $toolPlan = [pscustomobject]@{
            Type             = 'Tool'
            Name             = $toolName
            Description      = [string](Get-ConfigValue -Values $tool -Name 'description' -DefaultValue '')
            Phase            = $phase
            Command          = $toolCommand.Trim()
            Arguments        = ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $tool -Name 'args')
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

        $skill = ConvertTo-ConfigHashtable -InputObject $skillEntry.Value
        $scope = Resolve-SkillsScope -ConfigValues $values -Item $skill
        $projectPath = if ($scope -eq 'project') {
            $itemProjectPath = [string](Get-ConfigValue -Values $skill -Name 'projectPath' -DefaultValue (Get-ConfigValue -Values $values -Name 'projectPath' -DefaultValue ''))
            Resolve-SkillsProjectRoot -ProjectPath $itemProjectPath -BasePath $Config.BasePath
        }
        else {
            ''
        }

        $sourceInfo = Resolve-SkillsSource -SkillName $skillName -Item $skill -BasePath $Config.BasePath
        $agents = Resolve-SkillsAgents -ConfigValues $values -Item $skill -OverrideAgents $OverrideAgents
        $selectorOverride = @(ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $skill -Name 'skill'))
        $skillSelectors = if (@($selectorOverride).Count -gt 0) {
            $selectorOverride
        }
        elseif ($sourceInfo.IsLocal) {
            @()
        }
        else {
            @($skillName)
        }

        $copyValue = Get-ConfigValue -Values $skill -Name 'copy' -DefaultValue $false
        $allCommands = @(ConvertTo-SkillsCommandPlan -OwnerName $skillName -Commands (Get-ConfigValue -Values $skill -Name 'commands') -BasePath $Config.BasePath)
        $preCommands = @($allCommands | Where-Object { $_.Phase -eq 'preInstall' })
        $postCommands = @($allCommands | Where-Object { $_.Phase -eq 'postInstall' })
        foreach ($commandPlan in @($preCommands) + @($postCommands)) {
            $commandPlans.Add($commandPlan) | Out-Null
        }

        $skillPlan = [pscustomobject]@{
            Type             = 'Skill'
            Name             = $skillName
            Description      = [string](Get-ConfigValue -Values $skill -Name 'description' -DefaultValue '')
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

