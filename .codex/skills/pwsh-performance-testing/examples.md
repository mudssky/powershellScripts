# Examples

## 示例 1：用户说“profile 启动变慢了”

推荐动作：

```powershell
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1
```

如果需要快速回归检查，再补：

```powershell
$env:POWERSHELL_PROFILE_TIMING='1'
pwsh -NoLogo -c 'exit'
```

回复重点：

- 哪个 phase 变慢
- 是否与 starship / zoxide / proxy / aliases 有关
- 是否需要加隔离参数继续复测

## 示例 2：用户说“帮我比较命令发现逻辑的性能”

推荐动作：

```powershell
pnpm benchmark -- command-discovery
```

如果要产出 artifact：

```powershell
pnpm benchmark -- command-discovery -Iterations 8 -OutputPath ./artifacts/command-discovery.json
```

回复重点：

- `Find-ExecutableCommand` 与 `Get-Command` 的平均值和中位数
- 样本轮数
- 是否可以稳定复现速度差

## 示例 3：用户说“看一下 QA 最近的耗时情况”

推荐动作：

```powershell
pnpm qa:benchmark
```

如果需要自定义输出目录：

```powershell
pnpm qa:benchmark -- --output-dir ./artifacts/qa-benchmarks
```

回复重点：

- `latest.json`、时间戳样本、`summary.md` 的位置
- cold / warm / changed 三类场景的耗时
- 是否有失败任务或缓存异常

## 示例 4：用户说“这个 pwsh 热点还没有 benchmark，补一个”

推荐动作：

1. 先查看 `tests/benchmarks/` 是否已有相近 benchmark
2. 新增 `tests/benchmarks/<Name>.Benchmark.ps1`
3. 先参考 [best-practices.md](best-practices.md) 里的代码骨架
4. 保持 `-AsJson` / `-OutputPath` 语义一致
5. 给 `tests/Invoke-Benchmark.Tests.ps1` 或新测试文件补 smoke / 参数覆盖
6. 修改后运行 `pnpm qa`
7. 若涉及 pwsh 代码，再运行 `pnpm test:pwsh:all`

回复重点：

- 新 benchmark 的名字和用途
- 如何运行
- 新增了哪些测试
- 最终验证命令是什么

## 示例 5：用户说“这个 benchmark 数字很飘，帮我看方法对不对”

推荐动作：

1. 先确认它测的是冷启动还是热路径
2. 检查是否把 `Import-Module`、缓存预热、目录扫描等准备步骤混进计时
3. 检查是否交替执行 A/B，对照组是否存在顺序偏置
4. 检查是否在采样循环里使用 `+=`、`Write-Host`、`ConvertTo-Json`
5. 如有必要，按 [best-practices.md](best-practices.md) 的模式重写为 `Stopwatch + List[double] + -AsJson/-OutputPath`

回复重点：

- 当前 benchmark 的主要噪声来源
- 为什么现有数字不稳定或不可比
- 建议改成冷启动子进程、warm-up 或交替执行中的哪一种
- 是否需要补 `tests/Invoke-Benchmark.Tests.ps1` 风格的契约测试

## 示例 6：用户说“给这个 pwsh 模块补 Pester 测试”

推荐动作：

1. 先阅读 [pester-best-practices.md](pester-best-practices.md)
2. 确认测试文件是否遵守 Discovery / Run 双阶段
3. 用 `Describe` / `Context` / `It` 重写成可读的 BDD 结构
4. 只 Mock 网络、文件系统、外部 CLI 等边界依赖
5. 需要验证内部流程时，加 `Should -Invoke`
6. 修改后运行 `pnpm qa`
7. 若涉及 pwsh 代码，再运行 `pnpm test:pwsh:all`

回复重点：

- 新增或调整了哪些 `*.Tests.ps1`
- 用到了哪些 Mock，以及为什么只 Mock 这些边界
- 是否补了 XML / 覆盖率 / 配置对象相关建议
- 最终验证命令是什么
