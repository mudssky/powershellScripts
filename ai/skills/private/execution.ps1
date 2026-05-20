# skills 安装器私有 helper：安装检查、过滤与执行。
# 此文件由 Install-Skills.ps1 dot-source 加载，不作为独立入口运行。

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

    $exitCodes = ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $Check -Name 'exitCodes' -DefaultValue @('0')) |
        ForEach-Object { [int]$_ }
    if ($Result.ExitCode -notin $exitCodes) {
        return $false
    }

    $combinedOutput = "{0}`n{1}" -f $Result.StdOut, $Result.StdErr
    $contains = [string](Get-ConfigValue -Values $Check -Name 'contains' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($contains)) {
        return $combinedOutput.IndexOf($contains, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    $regex = [string](Get-ConfigValue -Values $Check -Name 'regex' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($regex)) {
        return [regex]::IsMatch($combinedOutput, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    return $true
}

function Test-SkillsToolInstalled {
    <#
    .SYNOPSIS
        判断 tool setup 是否已满足 check 条件。

    .PARAMETER Tool
        tool 安装计划项。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .PARAMETER SuppressOutput
        为真时临时重定向 check 输出，只保留日志记录。

    .OUTPUTS
        bool。check 满足时返回 true；未配置 check 或 check 未命中时返回 false。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Tool,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner,

        [switch]$SuppressOutput
    )

    if ($null -eq $Tool.Check) {
        return $false
    }

    $check = ConvertTo-ConfigHashtable -InputObject $Tool.Check
    if (Test-SkillsDirectoryCheck -Check $check) {
        return $true
    }

    $checkCommand = [string](Get-ConfigValue -Values $check -Name 'command')
    if ([string]::IsNullOrWhiteSpace($checkCommand)) {
        return $false
    }

    $checkArguments = ConvertTo-SkillsStringArray -Value (Get-ConfigValue -Values $check -Name 'args')
    $checkResult = & $CommandRunner $checkCommand $checkArguments $Tool.WorkingDirectory $LogPath $true ([bool]$SuppressOutput)

    return (Test-SkillsToolCheckResult -Check $check -Result $checkResult)
}

function Get-SkillsPendingPlan {
    <#
    .SYNOPSIS
        根据已安装检查生成仍需执行的安装计划。

    .DESCRIPTION
        计划展示前先检查 tool check 与本地 agent skill 目录，
        已满足的项目从执行计划中移除，避免重复安装。

    .PARAMETER Plan
        完整安装计划。

    .PARAMETER LogPath
        日志文件路径。

    .PARAMETER CommandRunner
        外部命令执行器，测试时可注入替身。

    .OUTPUTS
        PSCustomObject。包含过滤后的 Tools、Skills、Commands 与 Steps。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [AllowEmptyString()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [scriptblock]$CommandRunner
    )

    $pendingTools = [System.Collections.Generic.List[object]]::new()
    $pendingSkills = [System.Collections.Generic.List[object]]::new()
    $pendingCommands = [System.Collections.Generic.List[object]]::new()
    $pendingSteps = [System.Collections.Generic.List[object]]::new()
    $skippedTools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $skippedSkills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($tool in @($Plan.Tools)) {
        if (Test-SkillsToolInstalled -Tool $tool -LogPath $LogPath -CommandRunner $CommandRunner -SuppressOutput) {
            Write-Host "tool '$($tool.Name)' 已配置，跳过 setup。"
            Write-CommandLogLine -LogPath $LogPath -Message "SKIP tool $($tool.Name)"
            $skippedTools.Add([string]$tool.Name) | Out-Null
            continue
        }

        $pendingTools.Add($tool) | Out-Null
    }

    foreach ($skill in @($Plan.Skills)) {
        if (Test-SkillsSkillInstalled -Skill $skill) {
            Write-Host "skill '$($skill.Name)' 已安装，跳过安装。"
            Write-CommandLogLine -LogPath $LogPath -Message "SKIP skill $($skill.Name)"
            $skippedSkills.Add([string]$skill.Name) | Out-Null
            continue
        }

        $pendingSkills.Add($skill) | Out-Null
    }

    foreach ($step in @($Plan.Steps)) {
        if ($step.Type -eq 'Tool' -and $skippedTools.Contains([string]$step.Name)) {
            continue
        }

        if ($step.Type -eq 'Skill' -and $skippedSkills.Contains([string]$step.Name)) {
            continue
        }

        if ($step.Type -eq 'Command' -and $skippedSkills.Contains([string]$step.Owner)) {
            continue
        }

        $pendingSteps.Add($step) | Out-Null
        if ($step.Type -eq 'Command') {
            $pendingCommands.Add($step) | Out-Null
        }
    }

    return [pscustomobject]@{
        Tools    = [pscustomobject[]]$pendingTools.ToArray()
        Skills   = [pscustomobject[]]$pendingSkills.ToArray()
        Commands = [pscustomobject[]]$pendingCommands.ToArray()
        Steps    = [pscustomobject[]]$pendingSteps.ToArray()
    }
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

    if (-not $WhatIfPreference) {
        if (Test-SkillsToolInstalled -Tool $Tool -LogPath $LogPath -CommandRunner $CommandRunner) {
            Write-Host "tool '$($Tool.Name)' 已配置，跳过 setup。"
            Write-CommandLogLine -LogPath $LogPath -Message "SKIP tool $($Tool.Name)"
            return
        }
    }

    $target = "tool:$($Tool.Name)"
    $action = Format-NativeCommandLine -Command $Tool.Command -ArgumentList $Tool.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner $Tool.Command $Tool.Arguments $Tool.WorkingDirectory $LogPath $false $false | Out-Null
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
    $action = Format-NativeCommandLine -Command $CommandPlan.Command -ArgumentList $CommandPlan.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner $CommandPlan.Command $CommandPlan.Arguments $CommandPlan.WorkingDirectory $LogPath $false $false | Out-Null
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
        Write-CommandLogLine -LogPath $LogPath -Message "FORCE skill $($Skill.Name)"
    }

    $target = "skill:$($Skill.Name)"
    $action = Format-NativeCommandLine -Command 'npx' -ArgumentList $Skill.Arguments
    if ($PSCmdlet.ShouldProcess($target, $action)) {
        & $CommandRunner 'npx' $Skill.Arguments $Skill.WorkingDirectory $LogPath $false $false | Out-Null
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

