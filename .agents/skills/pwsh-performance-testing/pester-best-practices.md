# Pester Best Practices

## 目标

这份文档聚焦 Pester 5 测试本身，而不是 benchmark 设计。

适用场景：

- 给 PowerShell 脚本、模块或 profile 补 `*.Tests.ps1`
- 审查现有 Pester 测试是否跑得慢、结构混乱或容易污染环境
- 设计 Mock、CI 报告、覆盖率门禁
- 需要把一次性的验证脚本收敛成长期可维护的自动化测试

当前仓库的落地基线：

- 以 `Pester 5` 为前提
- 统一配置见 `PesterConfiguration.ps1`
- CI 测试结果当前使用 `NUnit3`
- PowerShell 相关代码改动最终仍需回到 `pnpm test:pwsh:all` 或 `pnpm test:pwsh:full`

## 1. 结构与生命周期

### 核心规则

- 不要在 `Describe` / `Context` 外层裸写会产生副作用或明显耗时的代码
- 一次性的重操作放 `BeforeAll`
- 每个 `It` 都需要重置的轻状态放 `BeforeEach`
- 批量生成测试用例需要动态数据时，用 `BeforeDiscovery`
- 临时文件、环境变量、全局函数等污染物必须在 `AfterAll` 或 `AfterEach` 清理

Pester 5 的关键点不是“能跑就行”，而是要尊重 Discovery / Run 双阶段。
如果在发现阶段执行了重逻辑，Pester 即使没有真正运行测试，也会先把这些成本吃掉。

### 示例：标准测试骨架

```powershell
<#
.SYNOPSIS
    演示符合 Pester 5 Discovery / Run 双阶段要求的测试结构。

.DESCRIPTION
    所有真正的初始化动作都放在 BeforeAll / BeforeEach / It 中，
    避免在发现阶段读取大文件、导入重模块或启动外部命令。
#>

Set-StrictMode -Version Latest

Describe 'Get-Widget' {
    BeforeAll {
        # BeforeAll 适合只做一次的昂贵准备工作，例如导入模块或读取大型夹具。
        $script:fixturePath = Join-Path $PSScriptRoot 'fixtures' 'widgets.json'
        $script:widgets = Get-Content -Path $script:fixturePath -Raw | ConvertFrom-Json
    }

    BeforeEach {
        # BeforeEach 只重置每个测试都需要干净刷新的轻量状态。
        $script:lastResult = $null
    }

    It '返回匹配 Id 的对象' {
        $script:lastResult = Get-Widget -Id 42 -InputObject $script:widgets

        $script:lastResult.Id | Should -Be 42
        $script:lastResult.Name | Should -Be 'core'
    }

    AfterAll {
        # 这里演示清理共享变量；真实项目里更常见的是删除临时目录或恢复环境变量。
        Remove-Variable -Name widgets, fixturePath, lastResult -Scope Script -ErrorAction SilentlyContinue
    }
}
```

### 示例：动态用例使用 `BeforeDiscovery`

```powershell
<#
.SYNOPSIS
    演示如何在 Discovery 阶段安全准备 `-ForEach` 数据源。

.DESCRIPTION
    只有“为了生成测试用例本身而必须提前得到的数据”才放在 BeforeDiscovery。
    真正的执行逻辑仍然放在 It / BeforeAll 中。
#>

BeforeDiscovery {
    # 这里只准备测试用例元数据，不做网络访问或大规模文件扫描。
    $script:cases = @(
        @{ Name = 'windows'; Input = 'C:\temp\demo.txt'; Expected = 'demo.txt' }
        @{ Name = 'unix'; Input = '/tmp/demo.txt'; Expected = 'demo.txt' }
    )
}

Describe 'Get-BaseName' -ForEach $script:cases {
    It '在 <Name> 路径上返回文件名' {
        Get-BaseName -Path $Input | Should -Be $Expected
    }
}
```

### 例外：极少数 Discovery 阶段准备

有些场景确实需要在发现阶段做最小准备，例如：

- `InModuleScope` 在发现阶段就要求模块已加载
- 某些 Mock 必须依附于预先存在的命令占位

这种情况可以做，但必须满足两个条件：

- 准备动作足够小，只服务测试解析
- 在测试文件旁边写清楚“为什么不能延后到 BeforeAll”

仓库里的 `psutils/tests/hardware.Tests.ps1` 就是这种例外：为了让 `InModuleScope` 和缺失命令的 Mock 能稳定挂载，先做了最小导入和占位函数声明。

## 2. 性能与断言优化

### 核心规则

- 默认优先使用原生 `Should`，除非已经明确遇到断言本身的性能瓶颈
- 在 `BeforeAll` 的关键初始化失败时，直接 `throw`，不要继续跑无意义测试
- 只有项目明确引入高性能断言工具时，才在热循环里考虑替换 `Should`
- 不要为了“快一点”把所有测试都改成难读的低级断言

当前仓库默认风格仍然是 `Should`，没有统一引入专门的 `Assert` 断言模块。
因此这里更合理的建议是“按需升级”，而不是把 `Should` 全部替换掉。

### 示例：默认使用 `Should`，初始化失败直接 `throw`

```powershell
<#
.SYNOPSIS
    演示 Pester 中默认的断言策略。

.DESCRIPTION
    普通行为验证继续使用 Should；
    如果关键测试数据准备失败，直接 throw 终止当前测试块，避免后续报错被噪声淹没。
#>

Describe 'Import-FeatureFlags' {
    BeforeAll {
        $script:fixturePath = Join-Path $PSScriptRoot 'fixtures' 'feature-flags.json'

        if (-not (Test-Path -LiteralPath $script:fixturePath)) {
            throw "缺少测试夹具: $script:fixturePath"
        }

        $script:flags = Get-Content -Path $script:fixturePath -Raw | ConvertFrom-Json
    }

    It '返回启用状态' {
        ($script:flags.experimental -eq $true) | Should -BeTrue
    }
}
```

### 示例：高频循环断言只在项目已引入 Assert 模块时使用

```powershell
<#
.SYNOPSIS
    演示高频断言的可选优化策略。

.DESCRIPTION
    只有项目已经显式引入 Assert 模块时，才建议在高频循环里采用这种写法。
    否则继续保留 Should，优先保证测试输出可读性。
#>

Describe 'Bulk validator' {
    It '在高频循环里保持断言成本可控' {
        $records = 1..1000 | ForEach-Object {
            [PSCustomObject]@{
                Id = $_
                IsValid = $true
            }
        }

        foreach ($record in $records) {
            # 非直观设计意图：这里假设项目已引入 Assert 模块，才切到更轻量的断言调用。
            # 若项目未引入，请改回 `$record.IsValid | Should -BeTrue`。
            Assert-True $record.IsValid "记录 $($record.Id) 应保持有效"
        }
    }
}
```

## 3. 命名与 BDD 规范

### 核心规则

- `Describe` 写“在测哪个函数、脚本或组件”
- `Context` 写“当前是什么场景、前置条件或输入状态”
- `It` 写“应该发生什么行为”
- `It` 名称不要再写“测试”两个字

推荐把一条测试标题读成一句完整的话：

- `Describe [Get-User]`
- `Context [当用户不存在时]`
- `It [抛出明确异常]`

### 示例：可读的 BDD 命名

```powershell
<#
.SYNOPSIS
    演示 Describe / Context / It 的命名分工。
#>

Describe 'Get-UserProfile' {
    Context '当用户文件存在时' {
        It '返回解析后的配置对象' {
            $result = Get-UserProfile -Path "$PSScriptRoot/fixtures/user.json"
            $result.Name | Should -Be 'Alice'
        }
    }

    Context '当用户文件不存在时' {
        It '抛出文件不存在异常' {
            { Get-UserProfile -Path "$PSScriptRoot/fixtures/missing.json" } | Should -Throw
        }
    }
}
```

## 4. Mock 的高级技巧

### 核心规则

- 只 Mock 外部边界和耗时操作，例如网络、文件系统、数据库、外部 CLI
- 优先验证“行为是否发生”，而不只是验证最终返回值
- Mock 尽量收敛在所属 `Context` 或 `BeforeEach`
- Mock 模块内部函数时，显式使用 `-ModuleName`
- 需要验证调用条件时，加 `-ParameterFilter`

### 示例：Mock 外部边界并验证调用行为

```powershell
<#
.SYNOPSIS
    演示如何把 Mock 限制在当前场景，并同时验证返回值与内部调用行为。
#>

Describe 'Invoke-HealthCheck' {
    Context '当远端接口返回 200 时' {
        BeforeEach {
            # Mock 外部网络边界，避免测试真的发起 HTTP 请求。
            Mock -CommandName Invoke-WebRequest -MockWith {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }
        }

        It '返回成功状态并调用一次网络请求' {
            $result = Invoke-HealthCheck -Url 'https://example.test/health'

            $result.IsHealthy | Should -BeTrue
            Should -Invoke -CommandName Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.test/health'
            }
        }
    }
}
```

### 示例：Mock 模块内部函数时带 `-ModuleName`

```powershell
<#
.SYNOPSIS
    演示针对模块内部函数的 Mock 写法。

.DESCRIPTION
    这种写法在仓库现有测试中很常见，适合隔离模块内部依赖而不影响其他模块。
#>

Describe 'Get-ProxyStatus' {
    BeforeEach {
        Mock -ModuleName proxy Write-Warning { }
        Mock -ModuleName proxy Get-Command {
            [PSCustomObject]@{
                Name = 'curl'
                Source = '/usr/bin/curl'
            }
        } -ParameterFilter { $Name -eq 'curl' }
    }

    It '在 curl 存在时返回可用状态' {
        $result = Get-ProxyStatus

        $result.HasCurl | Should -BeTrue
        Should -Invoke -CommandName Get-Command -ModuleName proxy -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'curl'
        }
    }
}
```

## 5. CI/CD 与工程化

### 核心规则

- 复杂执行参数优先收敛到 `New-PesterConfiguration`
- CI 中始终打开测试报告输出，当前仓库约定是 `NUnit3`
- 覆盖率只对稳定的源码范围开启，不要把生成代码和平台特定噪声带进去
- 覆盖率门槛要明确，但也要和项目成熟度匹配
- 本地调试与 CI 运行的路径、标签、并发度可以不同，但配置来源最好统一

仓库当前已经把这些约束沉淀到了 `PesterConfiguration.ps1`：

- `Run.Path` 会根据 `PWSH_TEST_MODE` 切换 `qa` / `full`
- `TestResult.OutputFormat` 当前为 `NUnit3`
- `CodeCoverage` 已支持环境变量覆盖
- `Output.Verbosity` 会区分本地与 CI

### 示例：用配置对象驱动 CI 测试

```powershell
<#
.SYNOPSIS
    演示面向 CI 的 Pester 配置对象写法。

.DESCRIPTION
    该示例展示常见的工程化开关：路径、并发、XML 报告、覆盖率与失败门禁。
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minimumCoverage = 80

$config = New-PesterConfiguration
$config.Run.Path = @('./psutils', './tests')
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Run.Parallel.Enabled = $true
$config.Run.Parallel.MaxThreads = 4
$config.Filter.ExcludeTag = @('Slow')
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnit3'
$config.TestResult.OutputPath = './artifacts/testResults.xml'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @('./psutils/modules/*.psm1')

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    throw "Pester 失败: $($result.FailedCount) 个测试未通过"
}

if ($null -ne $result.CodeCoverage -and $result.CodeCoverage.CoveragePercent -lt $minimumCoverage) {
    throw "覆盖率不足: $($result.CodeCoverage.CoveragePercent)% < $minimumCoverage%"
}
```

## 6. 写测试时的仓库落地建议

- 优先复用 `PesterConfiguration.ps1`，不要在命令行硬拼一长串参数
- 需要调试单个测试文件时，再临时缩小 `Run.Path`
- 对 `profile/**`、`psutils/**`、`tests/**/*.ps1` 的改动，最终验证要回到 `pnpm test:pwsh:all`
- Docker 不可用时，至少执行 `pnpm test:pwsh:full`，并在说明里注明 Linux 覆盖依赖 CI 或 WSL
- 测试里用到临时路径时，优先使用 `TestDrive` 或显式的临时目录清理策略

## 7. 常见反模式

- 在测试文件顶层直接执行 `Get-Content`、`Get-Process`、`Invoke-WebRequest`
- 把每个 `It` 都塞满重复初始化，导致同一份重数据反复加载
- 为了追求“快”，把所有 `Should` 都替换成难读断言
- 全局 Mock 一个命令，导致其他 `Context` 也意外吃到假数据
- 只断言返回值，不验证关键副作用和内部调用
- CI 有 XML 报告，却没有 `PassThru` 结果和失败门禁
- 覆盖率统计包含生成文件、缓存文件或明显不稳定的路径

## 8. 自检清单

- 测试文件是否尊重 Discovery / Run 双阶段
- `BeforeAll`、`BeforeEach`、`AfterAll` 的职责是否清晰
- Mock 是否只覆盖外部边界和当前场景
- `It` 名称是否表达行为，而不是“测试某某”
- 是否已经配置 XML 测试报告与必要的覆盖率门禁
- 失败时日志是否足够清晰，而不是被过量输出淹没
