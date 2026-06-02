# skills 安装器私有 helper：基础路径、agent 目录与已安装检查。
# 此文件由 Install-Skills.ps1 dot-source 加载，不作为独立入口运行。

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

function Resolve-SkillsUserHome {
    <#
    .SYNOPSIS
        解析当前用户主目录。

    .DESCRIPTION
        优先使用 .NET 标准用户目录，缺失时兼容常见环境变量，
        用于定位 Claude Code 与 Codex 的全局 skill 目录。

    .OUTPUTS
        string。当前用户主目录绝对路径。
    #>
    [CmdletBinding()]
    param()

    $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not [string]::IsNullOrWhiteSpace($userHome)) {
        return [System.IO.Path]::GetFullPath($userHome)
    }

    foreach ($envName in @('USERPROFILE', 'HOME')) {
        $envHome = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($envHome)) {
            return [System.IO.Path]::GetFullPath($envHome)
        }
    }

    throw '无法解析当前用户主目录。'
}

function Resolve-SkillsAgentSkillDirectory {
    <#
    .SYNOPSIS
        解析指定 agent 的全局 skill 目录。

    .DESCRIPTION
        根据安装计划中的 agent 名称定位本地 skill 根目录。
        测试和特殊环境可通过 `SKILLS_INSTALLER_CLAUDE_SKILLS_DIR`
        或 `SKILLS_INSTALLER_CODEX_SKILLS_DIR` 覆盖默认目录。

    .PARAMETER Agent
        安装计划中的 agent 名称，例如 `claude-code` 或 `codex`。

    .OUTPUTS
        string。支持的 agent 返回 skill 根目录；不支持时返回空字符串。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Agent
    )

    switch ($Agent.Trim().ToLowerInvariant()) {
        'claude-code' {
            $override = [Environment]::GetEnvironmentVariable('SKILLS_INSTALLER_CLAUDE_SKILLS_DIR', 'Process')
            if (-not [string]::IsNullOrWhiteSpace($override)) {
                return [System.IO.Path]::GetFullPath($override)
            }

            return (Join-Path (Join-Path (Resolve-SkillsUserHome) '.claude') 'skills')
        }
        'codex' {
            $override = [Environment]::GetEnvironmentVariable('SKILLS_INSTALLER_CODEX_SKILLS_DIR', 'Process')
            if (-not [string]::IsNullOrWhiteSpace($override)) {
                return [System.IO.Path]::GetFullPath($override)
            }

            $codexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
            if ([string]::IsNullOrWhiteSpace($codexHome)) {
                $codexHome = Join-Path (Resolve-SkillsUserHome) '.codex'
            }

            return (Join-Path ([System.IO.Path]::GetFullPath($codexHome)) 'skills')
        }
        default {
            return ''
        }
    }
}

function Resolve-SkillsInstalledNameCandidates {
    <#
    .SYNOPSIS
        生成用于本地目录检查的 skill 名称候选。

    .PARAMETER Skill
        单个 skill 安装计划项。

    .OUTPUTS
        string[]。去重后的目录名候选，优先包含配置项名称。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Skill
    )

    $names = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @([string]$Skill.Name) + @($Skill.SkillSelectors)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $seen.Add($candidate.Trim())) {
            $names.Add($candidate.Trim()) | Out-Null
        }
    }

    return [string[]]$names.ToArray()
}

function Test-SkillsAgentSkillInstalled {
    <#
    .SYNOPSIS
        判断某个 agent 目录中是否已存在指定 skill。

    .PARAMETER Agent
        安装计划中的 agent 名称。

    .PARAMETER SkillNames
        可能的 skill 目录名候选。

    .OUTPUTS
        bool。任一候选目录存在时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Agent,

        [Parameter(Mandatory)]
        [string[]]$SkillNames
    )

    $skillRoot = Resolve-SkillsAgentSkillDirectory -Agent $Agent
    if ([string]::IsNullOrWhiteSpace($skillRoot) -or -not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
        return $false
    }

    foreach ($skillName in $SkillNames) {
        $skillPath = Join-Path $skillRoot $skillName
        if (Test-Path -LiteralPath $skillPath) {
            return $true
        }
    }

    return $false
}

function Test-SkillsSkillInstalled {
    <#
    .SYNOPSIS
        判断安装计划中的 skill 是否已在目标 agent 中存在。

    .DESCRIPTION
        仅检查该 skill 配置实际声明的 agent。只要任一目标 agent 的
        skill 目录存在对应目录，就认为该 skill 已安装，避免重复执行
        `skills add`。

    .PARAMETER Skill
        单个 skill 安装计划项。

    .OUTPUTS
        bool。目标 agent 中任一处已存在时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Skill
    )

    $skillNames = Resolve-SkillsInstalledNameCandidates -Skill $Skill
    if (@($skillNames).Count -eq 0) {
        return $false
    }

    foreach ($agentName in @($Skill.Agents)) {
        if (Test-SkillsAgentSkillInstalled -Agent ([string]$agentName) -SkillNames $skillNames) {
            return $true
        }
    }

    return $false
}

function Test-SkillsDirectoryCheck {
    <#
    .SYNOPSIS
        根据 check 配置检查 agent skill 目录。

    .DESCRIPTION
        目录检查用于替代某些 CLI 自身不稳定的 list/check 输出。
        只要任一声明 agent 的 skill 目录下存在任一候选 skill 名称，
        就认为目标已安装。

    .PARAMETER Check
        check 配置节点，支持 `skill`、`skills`、`skillNames` 与 `agents`。

    .OUTPUTS
        bool。目录命中时返回 true，未配置目录检查或未命中时返回 false。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Check
    )

    $skillNames = @(
        ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Check -Name 'skill')
        ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Check -Name 'skills')
        ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Check -Name 'skillNames')
    )
    if (@($skillNames).Count -eq 0) {
        return $false
    }

    $agents = @(ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Check -Name 'agents' -DefaultValue @('claude', 'codex')))
    foreach ($agentName in $agents) {
        $mappedAgent = ConvertTo-SkillsCliAgent -Agent $agentName
        if (Test-SkillsAgentSkillInstalled -Agent $mappedAgent -SkillNames $skillNames) {
            return $true
        }
    }

    return $false
}

