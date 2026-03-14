BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'selection.psm1') -Force
}

Describe 'Select-InteractiveItem' {
    AfterEach {
        Remove-Item Function:\fzf -ErrorAction SilentlyContinue
        Remove-Item Function:\global:fzf -ErrorAction SilentlyContinue
    }

    Context '文本降级单选' {
        BeforeEach {
            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
            Mock -ModuleName selection Read-Host { return '2' }
            Mock -ModuleName selection Write-Host {}
        }

        It '在没有 fzf 时返回选中的字符串候选项' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta', 'gamma') -Prompt 'Pick'

            $result | Should -Be 'beta'
        }
    }

    Context '文本降级多选' {
        BeforeEach {
            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
            Mock -ModuleName selection Read-Host { return '3,1,3' }
            Mock -ModuleName selection Write-Host {}
        }

        It '在多选模式下按输入顺序去重并返回原始项' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta', 'gamma') -AllowMultiple -Prompt 'Pick'

            @($result).Count | Should -Be 2
            $result[0] | Should -Be 'gamma'
            $result[1] | Should -Be 'alpha'
        }
    }

    Context '文本降级非法输入重试' {
        BeforeEach {
            $script:SelectionResponses = [System.Collections.Generic.Queue[string]]::new()
            $script:SelectionResponses.Enqueue('x')
            $script:SelectionResponses.Enqueue('1')

            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
            Mock -ModuleName selection Read-Host { return $script:SelectionResponses.Dequeue() }
            Mock -ModuleName selection Write-Host {}
            Mock -ModuleName selection Write-Warning {}
        }

        It '遇到非法输入时提示后继续读取下一次输入' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta') -Prompt 'Pick'

            $result | Should -Be 'alpha'
            Should -Invoke Write-Warning -ModuleName selection -Times 1 -Exactly
        }
    }

    Context '取消选择' {
        BeforeEach {
            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
            Mock -ModuleName selection Read-Host { return '' }
            Mock -ModuleName selection Write-Host {}
        }

        It '单选取消时返回 null' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta') -Prompt 'Pick'

            $result | Should -Be $null
        }

        It '多选取消时返回空数组' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta') -AllowMultiple -Prompt 'Pick'

            @($result).Count | Should -Be 0
        }
    }

    Context '对象候选项' {
        BeforeEach {
            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
            Mock -ModuleName selection Read-Host { return '1' }
            Mock -ModuleName selection Write-Host {}
        }

        It '对象输入缺少显示逻辑时抛错' {
            $items = @(
                [PSCustomObject]@{ Name = 'alpha'; Value = 1 }
            )

            { Select-InteractiveItem -Items $items -Prompt 'Pick' -ErrorAction Stop } | Should -Throw
        }

        It '通过 DisplayProperty 返回原始对象引用' {
            $items = @(
                [PSCustomObject]@{ Name = 'alpha'; Value = 1 },
                [PSCustomObject]@{ Name = 'beta'; Value = 2 }
            )

            $result = Select-InteractiveItem -Items $items -DisplayProperty 'Name' -Prompt 'Pick'

            [object]::ReferenceEquals($result, $items[0]) | Should -BeTrue
        }

        It '通过 DisplayScriptBlock 返回原始对象引用' {
            $items = @(
                [PSCustomObject]@{ Name = 'alpha'; Value = 1 },
                [PSCustomObject]@{ Name = 'beta'; Value = 2 }
            )

            $result = Select-InteractiveItem `
                -Items $items `
                -DisplayScriptBlock { "{0}:{1}" -f $_.Name, $_.Value } `
                -Prompt 'Pick'

            [object]::ReferenceEquals($result, $items[0]) | Should -BeTrue
        }
    }

    Context 'fzf 路径' {
        BeforeEach {
            $script:FzfRows = [System.Collections.Generic.List[string]]::new()

            function global:fzf {
                begin {
                    $script:FzfRows.Clear()
                }

                process {
                    $script:FzfRows.Add([string]$_) | Out-Null
                }

                end {
                    $global:LASTEXITCODE = 0
                    Write-Output $script:FzfRows[1]
                }
            }

            Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $true }
        }

        It '检测到 fzf 时使用 fzf 结果映射回原始项' {
            $result = Select-InteractiveItem -Items @('alpha', 'beta') -Prompt 'Pick'

            $result | Should -Be 'beta'
            $script:FzfRows.Count | Should -Be 2
        }
    }

    It '通过 psutils manifest 导出 Select-InteractiveItem' {
        Import-Module (Join-Path $PSScriptRoot '..' 'psutils.psd1') -Force

        $command = Get-Command -Module psutils -Name Select-InteractiveItem
        $command | Should -Not -BeNullOrEmpty
    }
}
