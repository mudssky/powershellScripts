## Context

当前 Profile 在 Windows Full 模式下加载耗时约 2s，相比此前约 1s 有明显回归。同时 Tab 补全响应需数秒，严重影响日常使用体验。

通过代码走读和链路分析，**加载瓶颈**分布在以下环节：

1. **工具检测**（~100-200ms）：`Test-EXEProgram` 对 starship/zoxide/sccache/fnm 逐个调用 `Get-Command -CommandType Application`，每次扫描整个 PATH
2. **代理探测**（~100-300ms）：`Set-Proxy auto` 通过 TCP 连接检测代理可用性，超时 100ms + 连通后二次检测 200ms
3. **编码初始化**（~40ms）：`Set-ProfileUtf8Encoding` 中两次不限类型的 `Get-Command` 调用

**Tab 补全慢**的根因：

4. **starship 缓存形同虚设**：`Invoke-WithFileCache` 的 Generator `{ & starship init powershell }` 输出的是一行引导代码（`Invoke-Expression (& starship init powershell --print-full-init ...)`），而非完整初始化脚本。这导致缓存命中时 dot-source 仍会 spawn starship 进程。每次 prompt 渲染（包括 Tab 补全后刷新）都会启动一个 starship 外部进程。
5. **MenuComplete 模式**：要求一次性枚举所有候选项（~70 个 psutils 函数 + PATH 中所有可执行文件 + 别名 + 文件），在 PATH 很长时扫描开销大。
6. **PSModulePath 包含额外目录**：命令发现阶段需要扫描更多路径寻找自动加载模块。

约束条件：
- 不能破坏 Full/Minimal/UltraMinimal 三种模式的语义和行为
- `psutils` 模块功能必须完整保留
- 所有现有函数、别名、环境变量在 Full 模式下必须仍然可用
- profile 错误不得阻止 shell 启动

## Goals / Non-Goals

**Goals:**

- 将 Windows Full 模式加载时间降至 ~1s 以内（减少约 50%）
- 显著改善 Tab 补全响应速度（从数秒降至即时响应）
- 提供分阶段计时诊断能力，便于后续监控性能回归
- 保持所有现有功能和模式语义不变

**Non-Goals:**

- 不重写 psutils 模块架构（如编译为 .dll 二进制模块）
- 不拆分 psutils 的 Import-Module 加载（会影响 Tab 补全和函数可用性）
- 不修改 Minimal/UltraMinimal 模式的行为（这两个模式已经足够快）
- 不引入异步/并行 PowerShell Job 机制（复杂度过高，收益不确定）
- 不优化 starship/zoxide 上游初始化脚本本身的执行时间

## Decisions

### Decision 1: 修复 starship 缓存（收益最大）

**选择**：将 `Invoke-WithFileCache` 的 Generator 从 `{ & starship init powershell }` 改为 `{ & starship init powershell --print-full-init }`。

**问题分析**：`starship init powershell` 不加 `--print-full-init` 时输出的是一行引导代码：
```powershell
Invoke-Expression (& starship init powershell --print-full-init | Out-String)
```
缓存这段代码后 dot-source 时仍会调用 starship 二进制。加 `--print-full-init` 后输出约 200 行完整的 PowerShell 初始化脚本（包含 prompt 函数定义等），缓存后 dot-source 不再需要外部进程。

**替代方案**：
- 不缓存直接每次调用 → 每次启动都要 spawn starship 进程，更慢
- 在 prompt 函数中做异步渲染 → 改动太大，属于 starship 上游职责

**理由**：这是一行参数的修复，收益极大——消除了每次 prompt 渲染 spawn 外部进程的问题，直接解决 Tab 补全慢的核心根因。zoxide 缓存已确认是正确的（完整脚本约 130 行），无需修改。

### Decision 2: Tab 补全模式从 MenuComplete 切换回 Complete

**选择**：将 `Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete` 改为 `Set-PSReadLineKeyHandler -Key Tab -Function Complete`。

**替代方案**：
- 保持 MenuComplete + 优化候选源 → 根本问题无法解决，PowerShell 仍需一次性枚举全部候选
- 使用 PSReadLine Prediction 替代 → 互补关系，不冲突但不解决 Tab 问题

**理由**：`Complete` 模式只补全到最长公共前缀，多次 Tab 循环候选，不需要一次性扫描所有候选源。这是 PowerShell 的默认行为，用户已习惯。

### Decision 3: 批量工具检测替代逐个调用

**选择**：用单次 `Get-Command -Name @('starship','zoxide','sccache','fnm') -CommandType Application -ErrorAction SilentlyContinue` 批量查询替代 4 次独立 `Test-EXEProgram` 调用。

**替代方案**：
- 用 `[System.IO.File]::Exists()` 检查已知路径 → 不跨平台，需要维护路径表
- 用 `where.exe`/`which` 命令 → 启动外部进程更慢

**理由**：单次 `Get-Command` 批量查询比 4 次独立调用快，因为 PowerShell 内部会复用 PATH 扫描结果。

### Decision 4: 代理探测优化

**选择**：
1. 将 `Set-Proxy auto` 的 TCP 超时从 100ms 缩短为 50ms
2. 取消 `Set-Proxy on` 中的二次端口检测（200ms timeout），改为仅设置环境变量
3. 在 `Initialize-Environment` 中为 `Set-Proxy auto` 包装 `Invoke-WithCache` 缓存层，缓存有效期 5 分钟

**理由**：局域网代理 50ms 足以完成 TCP 握手；端口检测主要用于提示用户，不需要阻塞启动路径；缓存状态可以大幅减少重复探测。

### Decision 5: Get-Command 搜索范围收窄

**选择**：在 `Set-ProfileUtf8Encoding` 中：
- PSReadLine 是 pwsh 7 内置模块，直接调用 `Set-PSReadLineKeyHandler` 而不做 `Get-Command` 检查
- `Register-FzfHistorySmartKeyBinding` 加 `-CommandType Function` 限定搜索范围

**理由**：PSReadLine 在 PowerShell 7+ 中始终可用（是 profile 的运行时基线），无需检查。加 `-CommandType Function` 避免扫描 Application 类型。

### Decision 6: 精简 PSModulePath

**选择**：在 `profile/core/loadModule.ps1` 中不再将项目父目录追加到 `PSModulePath`，仅保留 PSModulePath 去重逻辑。

**替代方案**：
- 保持添加但在命令发现策略中优化 → PowerShell 不提供此级别控制

**理由**：额外的 PSModulePath 条目会导致 PowerShell 命令发现阶段扫描更多目录。项目父目录可能包含大量子目录，拖慢命令查找和 Tab 补全。psutils 模块通过显式 `Import-Module` 加载，不依赖 PSModulePath 自动发现。

### Decision 7: 分阶段计时诊断

**选择**：在 `profile.ps1` 中使用 `[System.Diagnostics.Stopwatch]` 对关键阶段计时，通过 `Verbose` 流输出，并在环境变量 `POWERSHELL_PROFILE_TIMING=1` 时输出到主机。

**理由**：Stopwatch 精度高、开销极小（微秒级），不影响正常加载性能。Verbose 流不干扰正常输出，环境变量开关便于按需启用。

## Risks / Trade-offs

- **[Risk] starship `--print-full-init` 输出在版本升级后可能变化** → Mitigation: 缓存有效期 7 天，升级 starship 后最多 7 天自动刷新；用户可手动删除 `.cache/starship-init-powershell.ps1` 强制重建。

- **[Risk] Complete 模式相比 MenuComplete 体验不同** → Mitigation: Complete 是 PowerShell 默认行为；如果用户不适应可以随时在 encoding.ps1 改回。

- **[Risk] 缓存代理状态可能导致代理切换后延迟生效** → Mitigation: 缓存有效期仅 5 分钟，用户可通过 `Set-Proxy on/off` 手动刷新。

- **[Risk] 移除 PSModulePath 中的额外路径可能影响某些自动加载场景** → Mitigation: psutils 通过显式 Import-Module 加载，不依赖自动发现。如果有其他模块依赖此路径，会在测试阶段发现。

- **[Risk] 批量 Get-Command 的结果顺序** → Mitigation: 用 `.Name` 属性做 HashSet 查找，不依赖顺序。
