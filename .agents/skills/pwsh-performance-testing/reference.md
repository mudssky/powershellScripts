# Reference

## 场景到命令映射

| 场景 | 首选命令 | 目的 |
|---|---|---|
| 查看现有 benchmark | `pnpm benchmark -- --list` | 避免猜 benchmark 名 |
| 比较命令发现冷启动 | `pnpm benchmark -- command-discovery` | 对比 `Find-ExecutableCommand` 与 `Get-Command` |
| 比较帮助搜索实现 | `pnpm benchmark -- help-search` | 观察自定义解析与 `Get-Help` 路径差异 |
| 诊断 profile 分阶段耗时 | `pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1` | 找出具体慢在哪个阶段 |
| 快速看 profile 总耗时 | `$env:POWERSHELL_PROFILE_TIMING='1'; pwsh -NoLogo -c 'exit'` | 低成本回归检查 |
| 采样 QA 趋势 | `pnpm qa:benchmark` | 比较 `qa` 与 `turbo:qa` 的冷/热/变更路径 |
| 验证 profile 专项测试 | `pnpm test:pwsh:profile` | 检查 profile 测试隔离场景 |

## 推荐执行顺序

### profile 启动问题

1. 运行 `pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1`
2. 如果热点不明显，再加隔离参数重跑
3. 若涉及改动前后对比，记录同一机器、同一 shell、同一环境变量下的两组结果
4. 若改动了 profile 或 psutils 代码，补跑 `pnpm qa` 与 `pnpm test:pwsh:all`

### 已有 benchmark 问题

1. 运行 `pnpm benchmark -- --list`
2. 选择目标 benchmark
3. 需要落盘时优先使用 `-OutputPath`
4. 需要脚本消费时优先使用 `-AsJson`
5. 结论里同时给出人类可读摘要与 artifact 路径

### QA 趋势问题

1. 运行 `pnpm qa:benchmark`
2. 检查 `artifacts/qa-benchmarks/latest.json`
3. 对照 `summary.md` 汇报 cold / warm / changed 场景
4. 如有失败，顺带汇报失败任务和缓存摘要

## 设计方法入口

如果当前任务是在“设计或重写 benchmark”，不要继续在本文件里找，直接看 [best-practices.md](best-practices.md)。

该文件集中说明：

- 如何区分冷启动 / 热路径
- 如何用低噪声方式采样
- 如何设计 `-AsJson` / `-OutputPath`
- 哪些检查适合放进 Pester / CI
- 常见反模式及对应代码示例

如果当前任务是在“设计或审查 Pester 测试本身”，直接看 [pester-best-practices.md](pester-best-practices.md)。

## 新增 benchmark 的仓库约定

### 文件命名

- 使用 `tests/benchmarks/<Name>.Benchmark.ps1`
- 会自动映射成 kebab-case benchmark 名
- 例如 `CommandDiscovery.Benchmark.ps1` 会暴露为 `command-discovery`

### 参数设计

建议公共参数：

- `-OutputPath`：把 JSON 结果写到文件
- `-AsJson`：只输出 JSON，避免彩色日志污染 stdout
- 需要时补 `-Iterations`、`-SearchTerm`、`-CommandNames` 这类场景参数

### 输出设计

- 交互运行时可以保留可读摘要
- 脚本消费时保持 stdout 干净
- 结果对象中至少包含：
  - 生成时间
  - 平台
  - 关键输入参数
  - 平均值 / 中位数 / min / max / 样本列表
  - 限制说明或 notes

### 测量设计

- 冷启动问题优先在新的 `pwsh -NoProfile` 子进程里测
- 样本收集优先用 `[System.Collections.Generic.List[double]]`
- 计时优先用 `[System.Diagnostics.Stopwatch]`
- 先测量原始值，最后再做四舍五入展示
- 避免把模块导入、彩色输出或目录扫描噪声混进目标测量
- 对照组优先交替执行，而不是先跑完 A 再跑完 B
- 热路径测试先做最小 warm-up，再开始正式采样
- 不要在 benchmark 主循环里做网络请求、交互输入或无关的文件系统遍历

### 测试设计

新增 benchmark 后，至少补这些验证：

- 能被 `pnpm benchmark -- --list` 发现
- 显式名称执行成功
- `-OutputPath` 正常落盘
- `-AsJson` 输出可被脚本解析
- 关键参数能覆盖核心分支
- 尽量只校验结构、路由和契约，不把易抖动的绝对耗时写成单元测试硬阈值

仓库里现成参考：

- `tests/benchmarks/CommandDiscovery.Benchmark.ps1`
- `tests/benchmarks/HelpSearch.Benchmark.ps1`
- `tests/Invoke-Benchmark.Tests.ps1`

## 结果汇报模板

可以按下面结构汇报：

```markdown
场景：profile 启动回归
命令：pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1
环境：Windows / pwsh 7.x / 本地 host
结果：Phase 4 从 286ms 上升到 514ms，热点集中在工具初始化
Artifacts：artifacts/... 或控制台输出
判断：回归主要来自 starship 初始化，而不是模块同步加载
建议：先用 -SkipStarship 复测；若确认，检查缓存命中和外部进程调用次数
```

## 仓库内可复用资料

- `README.md` 中的 benchmark 与 QA 采样说明
- `profile/README.md` 中的 profile 性能基线与诊断方法
- `docs/cheatsheet/pwsh/高性能pwsh最佳实践.md` 中的 PowerShell 常见性能陷阱
