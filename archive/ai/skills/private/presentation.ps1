# skills 安装器私有 helper：安装计划展示与确认。
# 此文件由 Install-Skills.ps1 dot-source 加载，不作为独立入口运行。

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
            Write-Host ("  {0}" -f (Format-NativeCommandLine -Command $tool.Command -ArgumentList $tool.Arguments))
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
            Write-Host ("  {0}" -f (Format-NativeCommandLine -Command 'npx' -ArgumentList $skill.Arguments))
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

    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', '执行以上安装计划。'),
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', '取消安装计划。')
    )
    $selected = $Host.UI.PromptForChoice('确认安装计划', '继续执行以上安装计划？', $choices, 1)
    return $selected -eq 0
}

