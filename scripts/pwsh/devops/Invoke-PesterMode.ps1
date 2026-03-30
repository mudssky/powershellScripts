#!/usr/bin/env pwsh

<#
.SYNOPSIS
    以统一方式按模式执行仓库内的 Pester 配置。

.DESCRIPTION
    该脚本是对 `PesterConfiguration.ps1` 的轻量包装，用于把“设置测试模式环境变量”
    和“调用统一配置”收敛到一个 `pwsh -File` 入口中，避免在 `package.json` 里继续
    使用容易被 Unix shell 提前展开的 `pwsh -Command "$env:..."` 形式。

.PARAMETER Mode
    Pester 运行模式，对应 `PWSH_TEST_MODE`。常见值包括 `full`、`qa`、`serial`。

.PARAMETER Coverage
    Coverage 行为：
    - `Default`: 不显式覆盖，交给 `PesterConfiguration.ps1` 按模式决定
    - `On`: 显式启用 coverage
    - `Off`: 显式关闭 coverage

.PARAMETER VerboseOutput
    是否启用详细输出，对应 `PWSH_TEST_VERBOSE=1`。

.PARAMETER Path
    可选的单文件或子集测试路径，对应 `PWSH_TEST_PATH`。

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa

    以 QA 模式运行默认的快速 Pester 子集。

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode full -Coverage Off

    以 full 模式运行，但显式关闭 coverage。
#>
[CmdletBinding()]
param(
    [ValidateSet('full', 'fast', 'qa', 'serial', 'debug')]
    [string]$Mode = 'full',

    [ValidateSet('Default', 'On', 'Off')]
    [string]$Coverage = 'Default',

    [switch]$VerboseOutput,

    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
$configPath = Join-Path $repoRoot 'PesterConfiguration.ps1'

$originalValues = @{
    PWSH_TEST_MODE            = [Environment]::GetEnvironmentVariable('PWSH_TEST_MODE', 'Process')
    PWSH_TEST_ENABLE_COVERAGE = [Environment]::GetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'Process')
    PWSH_TEST_VERBOSE         = [Environment]::GetEnvironmentVariable('PWSH_TEST_VERBOSE', 'Process')
    PWSH_TEST_PATH            = [Environment]::GetEnvironmentVariable('PWSH_TEST_PATH', 'Process')
}

function Restore-ProcessEnvironmentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
        return
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('PWSH_TEST_MODE', $Mode, 'Process')

    switch ($Coverage) {
        'On' {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'true', 'Process')
        }
        'Off' {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'false', 'Process')
        }
        default {
            Remove-Item Env:\PWSH_TEST_ENABLE_COVERAGE -ErrorAction SilentlyContinue
        }
    }

    if ($VerboseOutput.IsPresent) {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_VERBOSE', '1', 'Process')
    }
    else {
        Remove-Item Env:\PWSH_TEST_VERBOSE -ErrorAction SilentlyContinue
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Remove-Item Env:\PWSH_TEST_PATH -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_PATH', $Path, 'Process')
    }

    $configuration = & $configPath
    $configuration.Run.Exit = $true
    Invoke-Pester -Configuration $configuration
}
finally {
    foreach ($entry in $originalValues.GetEnumerator()) {
        Restore-ProcessEnvironmentValue -Name $entry.Key -Value $entry.Value
    }
}
