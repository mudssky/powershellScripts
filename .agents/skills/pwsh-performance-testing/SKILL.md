---
name: pwsh-performance-testing
description: 运行和分析 PowerShell 性能测试、benchmark、profile 启动耗时与回归定位，并指导新增高质量 benchmark。用于用户提到 pwsh 性能、benchmark、启动变慢、性能回归、冷启动对比、qa benchmark、profile timing、Measure-Command、基准设计、结果波动或 Pester 性能诊断时。
argument-hint: "[场景或目标，例如 profile 启动变慢]"
disable-model-invocation: true
---

# PowerShell 性能测试

用于在这个仓库里执行 `pwsh` 性能测量、定位回归，并输出可复现的结论。

## Quick Start

1. 先判断问题类型，再选最小测量入口。
2. 优先复用仓库现成入口，不要临时拼测量脚本。
3. 输出结论时必须带命令、环境、样本位置、测量口径和下一步建议。

常用入口：

```powershell
# 查看当前可用 benchmark
pnpm benchmark -- --list

# 跑单个 benchmark
pnpm benchmark -- command-discovery

# 诊断 profile 启动阶段耗时
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1

# 采样 QA 冷/热路径耗时
pnpm qa:benchmark
```

详细流程见 [reference.md](reference.md)，典型用法见 [examples.md](examples.md)。
如果任务涉及“怎么把性能测试做准、做稳、做快”，直接阅读 [best-practices.md](best-practices.md)。
如果任务涉及 Pester 测试结构、生命周期、Mock、命名或 CI 配置，直接阅读 [pester-best-practices.md](pester-best-practices.md)。

## Instructions

### 1. 先归类场景

把用户请求归到以下四类之一：

- `已有 benchmark 对比`：直接运行 `pnpm benchmark -- <name>`
- `profile 启动变慢`：优先跑 `profile/Debug-ProfilePerformance.ps1`
- `QA / CI 趋势采样`：运行 `pnpm qa:benchmark`
- `缺少测量入口`：新增或补强 `tests/benchmarks/*.Benchmark.ps1`

如果用户没有给出 benchmark 名称，先运行：

```powershell
pnpm benchmark -- --list
```

### 2. 先读最小上下文

执行前优先确认以下信息：

- `package.json` 中相关脚本
- `README.md` / `CLAUDE.md` 中已有 benchmark 说明
- 目标脚本、模块或测试文件
- 已有 `tests/benchmarks/*.Benchmark.ps1` 是否已经覆盖该场景

只加载当前任务需要的文件，避免把整个仓库都当成性能问题上下文。

### 3. 选择测量入口

#### A. benchmark 场景

优先使用仓库统一入口，而不是手写 ad-hoc 命令：

```powershell
pnpm benchmark -- --list
pnpm benchmark -- help-search
pnpm benchmark -- command-discovery
```

需要机器可读结果时，优先使用 benchmark 自带 `-OutputPath` 或 `-AsJson`。

#### B. profile 启动场景

先用完整分阶段诊断：

```powershell
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1
```

需要快速看总耗时时，再用：

```powershell
$env:POWERSHELL_PROFILE_TIMING='1'
pwsh -NoLogo -c 'exit'
```

如果需要隔离具体热点，优先尝试 `Debug-ProfilePerformance.ps1` 的可选参数，如 `-SkipStarship`、`-SkipZoxide`、`-SkipProxy`、`-SkipAliases`、`-Phase`。

#### C. QA / CI 趋势场景

当用户要比较 `qa` / `turbo:qa` 的冷启动、热启动或 PR 变更耗时，运行：

```powershell
pnpm qa:benchmark
```

必要时通过 `--output-dir` 指定输出目录，并汇报 `latest.json`、带时间戳样本和 `summary.md`。

### 4. 按任务类型选择最佳实践文档

#### A. benchmark / profile / 性能回归

优先看 [best-practices.md](best-practices.md)，里面包含：

- 冷启动 / 热路径口径拆分
- `Stopwatch + List[double]` 采样骨架
- A/B 交替执行示例
- 结构化输出示例
- 性能测试自检清单

#### B. Pester 测试设计 / Mock / CI

优先看 [pester-best-practices.md](pester-best-practices.md)，里面包含：

- Discovery / Run 双阶段约束
- `BeforeAll` / `BeforeEach` / `BeforeDiscovery` / `AfterAll` 用法
- `Should`、`throw` 与可选高性能断言策略
- BDD 命名规范
- Mock 与 `Should -Invoke` 示例
- `New-PesterConfiguration`、XML 报告与覆盖率门禁示例

### 5. 解释结果时遵守这些规则

- 先报告命令、平台、PowerShell 版本、样本轮数
- 再报告平均值、中位数、最慢值，不只报单次结果
- 明确说明是否是冷启动、热启动、缓存命中或容器环境
- 不把 benchmark 结果包装成绝对结论，除非样本足够稳定
- 涉及 host / linux 差异时，分别汇报，不合并成一个数字

### 6. 需要新增 benchmark 时

新增 benchmark 时遵守仓库现有模式：

- 文件位置：`tests/benchmarks/*.Benchmark.ps1`
- 通过 `scripts/pwsh/devops/Invoke-Benchmark.ps1` 自动发现
- 默认支持结构化输出，优先提供 `-OutputPath` 与 `-AsJson`
- 测量前启用 `Set-StrictMode -Version Latest`
- 冷启动测量优先使用新的 `pwsh -NoProfile` 子进程，避免当前会话污染
- 非交互脚本输出保持干净，避免噪声影响 JSON / 测量结果
- 对照实验优先交替执行不同实现，减少缓存和顺序偏置
- 采样循环里避免 `+=`、`Write-Host`、`ConvertTo-Json`、目录全量扫描等额外开销
- 如果 benchmark 结果需要长期比较，结果对象里写清楚测量口径、排除项和限制说明

实现细节和检查清单见 [reference.md](reference.md)。
benchmark 设计方法和代码示例见 [best-practices.md](best-practices.md)。
Pester 测试设计方法和代码示例见 [pester-best-practices.md](pester-best-practices.md)。

### 7. 变更后的验证

如果这个任务只是在读数据和跑性能测试，不需要额外执行 `pnpm qa`。

如果你为了完成任务修改了代码：

```powershell
pnpm qa
```

如果改动涉及 PowerShell 相关路径，还要执行：

```powershell
pnpm test:pwsh:all
```

若本机 Docker 不可用，至少执行：

```powershell
pnpm test:pwsh:full
```

并明确说明 Linux 覆盖依赖 CI 或 WSL。

## Output

最终回复至少包含：

- 你运行了什么命令
- 结果落在哪些文件
- 关键耗时或速度提升数据
- 测量口径、排除项或样本策略
- 你的判断依据
- 下一步建议
