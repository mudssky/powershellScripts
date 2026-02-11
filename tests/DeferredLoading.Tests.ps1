Set-StrictMode -Version Latest

<#
.SYNOPSIS
    延迟加载防护栏 — 静态 Pester 测试
.DESCRIPTION
    扫描 profile 同步路径文件中的 Get-Command -Name 调用，验证引用的函数名
    属于 6 个核心子模块的导出函数集合，防止 PSModulePath 自动导入 psutils 全量模块。
#>

Describe '延迟加载防护栏' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ProfileRoot = Join-Path $script:ProjectRoot 'profile'
        $script:PsutilsModulesDir = Join-Path $script:ProjectRoot 'psutils' 'modules'

        # 10.1: 收集 6 个核心子模块的导出函数列表
        $script:CoreModuleNames = @('os', 'cache', 'test', 'env', 'proxy', 'wrapper')
        $script:CoreFunctions = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($mod in $script:CoreModuleNames) {
            $modPath = Join-Path $script:PsutilsModulesDir "$mod.psm1"
            if (-not (Test-Path $modPath)) { continue }

            # 导入模块到临时作用域以获取导出函数
            $tempModule = Import-Module $modPath -PassThru -Force -ErrorAction Stop
            foreach ($fn in $tempModule.ExportedFunctions.Keys) {
                $script:CoreFunctions.Add($fn) | Out-Null
            }
            Remove-Module $tempModule -Force -ErrorAction SilentlyContinue
        }

        # 10.2: 扫描同步路径文件中的 Get-Command -Name 调用
        # 同步路径文件：profile/core/*.ps1 和 profile/features/*.ps1
        # 排除 loadModule.ps1 中 OnIdle Action 内部的调用（它们在延迟阶段执行）
        $script:SyncPathFiles = @()
        $script:SyncPathFiles += Get-ChildItem -Path (Join-Path $script:ProfileRoot 'core') -Filter '*.ps1' -File |
            Where-Object { $_.Name -ne 'loadModule.ps1' } |
            Select-Object -ExpandProperty FullName
        $script:SyncPathFiles += Get-ChildItem -Path (Join-Path $script:ProfileRoot 'features') -Filter '*.ps1' -File |
            Select-Object -ExpandProperty FullName
    }

    It '核心模块导出函数列表不为空' {
        $script:CoreFunctions.Count | Should -BeGreaterThan 0
    }

    It '同步路径中 Get-Command -Name 引用的函数 SHALL 属于核心模块导出函数集合' {
        # 10.3: 交叉验证
        $violations = [System.Collections.Generic.List[string]]::new()

        # 正则匹配 Get-Command -Name <函数名> 模式
        # 支持：Get-Command -Name FuncName、Get-Command -Name 'FuncName'、Get-Command -Name "FuncName"
        # 也支持简写：Get-Command FuncName（第一个位置参数）
        # 排除 -CommandType Application（查找外部可执行文件，不触发模块自动导入）
        $getCommandPattern = 'Get-Command\s+(-Name\s+)?[''"]?([A-Za-z][\w-]+)[''"]?'

        foreach ($file in $script:SyncPathFiles) {
            $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            $fileName = Split-Path -Leaf $file

            # 逐行扫描以获取行号
            $lines = Get-Content -Path $file -ErrorAction SilentlyContinue
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]

                # 跳过注释行
                if ($line -match '^\s*#') { continue }

                # 跳过包含 -CommandType Application 的行（外部可执行文件查找）
                if ($line -match '-CommandType\s+Application') { continue }

                # 匹配 Get-Command -Name <函数名> 或 Get-Command <函数名>
                if ($line -match $getCommandPattern) {
                    $funcName = $Matches[2]

                    # 跳过明显不是 psutils 函数的名称（如内置 cmdlet 或变量引用）
                    if ($funcName -match '^\$') { continue }

                    # 检查是否属于核心模块
                    if (-not $script:CoreFunctions.Contains($funcName)) {
                        # 进一步验证：检查该函数是否属于 psutils 的 FunctionsToExport
                        # 如果不属于 psutils，则无需告警（它不会触发 psutils 自动导入）
                        $manifestPath = Join-Path $script:ProjectRoot 'psutils' 'psutils.psd1'
                        $manifestData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction SilentlyContinue
                        if ($manifestData -and $manifestData.FunctionsToExport -contains $funcName) {
                            $violations.Add("$fileName`:$($i + 1): Get-Command 引用了非核心模块函数 '$funcName'，这会通过 PSModulePath 触发 psutils 全量自动导入")
                        }
                    }
                }
            }
        }

        if ($violations.Count -gt 0) {
            $message = "发现 $($violations.Count) 处同步路径中引用非核心模块函数的 Get-Command 调用:`n" +
                ($violations -join "`n")
            $violations.Count | Should -Be 0 -Because $message
        }
    }
}
