# Context

当前 `profile/` 目录下维护两个平台入口脚本：

- `profile.ps1`（~300 行）：Windows 平台 Profile
- `profile_unix.ps1`（~274 行）：Linux/macOS 平台 Profile

两者共享约 70% 的逻辑（`Set-AliasProfile`、`Initialize-Environment`、`Show-MyProfileHelp`、工具初始化、`z` 懒加载），真正的平台差异仅约 25-30 行。长期双文件维护已导致功能漂移：Unix 版缺少 `wrapper.ps1` 加载、`Show-MyProfileHelp` 不完整、无加载耗时统计。

## Goals / Non-Goals

**Goals:**

- 消除两个 profile 文件之间的代码重复，统一为单一入口
- 保持向后兼容，已有的 `$PROFILE` 引用路径不受影响
- Unix 平台获得与 Windows 一致的完整功能
- 统一 `LoadProfile` 逻辑为 `Set-PowerShellProfile` 函数方式

**Non-Goals:**

- 不重构 `psutils` 模块内部实现
- 不修改 `loadModule.ps1`、`wrapper.ps1`、`user_aliases.ps1` 的接口
- 不引入新的外部依赖
- 不改变工具初始化的缓存策略（`Invoke-WithFileCache`）

## Decisions

### 1. 合并策略：单文件 + 条件分支

**选择**: 将所有逻辑合并到 `profile.ps1`，使用 `$IsWindows`/`$IsLinux`/`$IsMacOS` 内置变量做条件分支。

**替代方案**: 抽取共享逻辑到 `profile_common.ps1`，两个入口文件只写差异代码。

**理由**: 平台差异仅 ~10%，不值得为此维护三个文件。PowerShell 7+ 内置了 `$IsWindows`/`$IsLinux`/`$IsMacOS` 变量，条件分支成本极低。单文件方案维护成本最低，且不增加调用链深度。

### 2. profile_unix.ps1 保留为薄 shim

**选择**: `profile_unix.ps1` 改为仅一行转发：`. $PSScriptRoot/profile.ps1 @PSBoundParameters`

**理由**: 已有用户的 `$PROFILE` 可能指向 `profile_unix.ps1`，直接删除会破坏现有环境。薄 shim 零维护成本，且提供清晰的迁移路径。

### 3. LoadProfile 统一为 Set-PowerShellProfile 函数

**选择**: 采用 `profile_unix.ps1` 的 `Set-PowerShellProfile` 函数方式，替代 `profile.ps1` 的内联 param 逻辑。

**理由**: 函数方式职责更清晰（SRP），可独立调用和测试。内联 param 方式将 profile 安装逻辑与环境初始化逻辑耦合在同一个控制流中。

### 4. Show-MyProfileHelp 以 Windows 版为基准合并

**选择**: 采用 `profile.ps1` 的完整版 `Show-MyProfileHelp`（包含函数别名、自定义函数包装、持久环境变量显示），并确保跨平台兼容。

**理由**: Windows 版功能更完整，Unix 版是功能子集。合并时以超集为准，避免功能退化。

### 5. 工具初始化表合并

**选择**: 统一 `$tools` 哈希表，所有工具共存，每个工具的 ScriptBlock 内部通过平台检查或 `$SkipTools` 控制是否执行。

| 工具 | 平台 |
| ---- | ---- |
| starship | 通用 |
| zoxide | 通用 |
| sccache | 仅 Windows |
| fnm | 仅 Unix |

**理由**: 统一工具表便于维护和扩展，平台判断内聚在各工具的 ScriptBlock 中。

### 6. $IsWindows 兼容性处理

**选择**: 在脚本顶部添加 `$IsWindows` 兼容性检查。在 Windows PowerShell 5.1 中 `$IsWindows` 未定义，需要回退判断。

```powershell
if ($null -eq $IsWindows) { $IsWindows = $true; $IsLinux = $false; $IsMacOS = $false }
```

**理由**: 虽然目标是 PowerShell 7+，但添加此兼容性检查成本极低，可防止在 Windows PowerShell 5.1 下意外加载时出错。

## Risks / Trade-offs

- **[风险] 合并后文件变长** → 预计 ~320-350 行，仍在可维护范围内。平台分支代码通过注释清晰标注。
- **[风险] 已有 profile_unix.ps1 引用** → 通过薄 shim 转发保持兼容，零破坏性。
- **[风险] 合并过程中遗漏功能** → 逐函数对比合并，以功能超集为准，合并后在 Linux 环境实际加载验证。
- **[权衡] 单文件 vs 多文件** → 选择单文件牺牲了一定的关注点分离，但换取了显著的维护简便性。对于 ~30 行的平台差异，这是合理的权衡。
