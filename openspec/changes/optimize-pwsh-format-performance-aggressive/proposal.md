## Why

`pnpm format:pwsh` 在本地反馈链路中明显偏慢：即使没有改动文件也要等待数秒，且在部分脚本上默认 `Invoke-Formatter` 规则会触发数十秒级耗时。当前成本已经影响日常迭代效率，需要一套以“速度优先”为目标的激进优化方案。

## What Changes

- 将 `-GitChanged` 流程改为“先判定改动再加载模块”，无改动时快速退出。
- 移除高成本的模块预扫描（`Get-Module -ListAvailable`），改为直接 `Import-Module` 并在失败时处理安装路径。
- 在 npm 脚本中统一改为 `pwsh -NoProfile`，降低启动抖动。
- 为 `Invoke-Formatter` 引入“激进性能配置”，排除高耗时规则（重点是 `PSUseCorrectCasing`），只保留核心排版规则。
- 优化目录扫描与写回策略（单次遍历筛选扩展名，格式化结果未变化时不写盘）。
- 增加“严格模式”入口以保留历史行为，用于需要完整规则的场景。

## Capabilities

### New Capabilities
- `pwsh-format-performance`: 定义 PowerShell 格式化的快速执行路径、激进规则集与严格模式切换行为。

### Modified Capabilities
- (none)

## Impact

- `scripts/pwsh/devops/Format-PowerShellCode.ps1` 的执行流程与参数行为。
- `package.json` 中 `format:pwsh` / `format:pwsh:all` / 相关 QA 链路的启动参数。
- 代码风格输出可能出现差异（尤其是大小写修正规则），需要通过“严格模式”兜底。
