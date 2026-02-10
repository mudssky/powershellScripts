## Why

当前 `profile/profile.ps1` 已有“精简模式”，但在自动化/沙盒场景下仍存在两类问题：
- 启动路径仍偏重（先加载 `psutils` 全量模块，再执行若干初始化），整体耗时高
- 某些外部工具初始化（如 starship/fnm/bash PATH 同步）在受限环境下易出现告警或阻塞

用户目标是“极简模式”，不仅要减少报错，还要显著缩短会话初始化时间，并保持最小可用能力。

## What Changes

- 新增“极简模式（Ultra Minimal）”语义，作为现有 `Minimal` 的更强约束模式
- 在极简模式下，`profile/profile.ps1` 仅保留最小能力：
  - UTF8 编码设置
  - 项目根环境变量（`POWERSHELL_SCRIPTS_ROOT`）
  - 必要的基础变量兼容（`$IsWindows/$IsLinux/$IsMacOS` 回退）
- 极简模式下显式禁用：
  - `psutils` 全量模块加载
  - 代理自动检测
  - Linux PATH 与 Bash 同步
  - Starship/Zoxide/fnm/sccache 初始化
  - 别名与包装函数注册
  - 帮助函数中依赖 `psutils` 的段落（改为可降级输出）

## Mode Differences

| 能力项 | Full（默认） | Minimal（现有） | UltraMinimal（新增） |
|---|---|---|---|
| UTF8 编码设置 | ✅ | ✅ | ✅ |
| `$IsWindows/$IsLinux/$IsMacOS` 兼容回退 | ✅ | ✅ | ✅ |
| `POWERSHELL_SCRIPTS_ROOT` | ✅ | ✅ | ✅ |
| `psutils` 模块加载 | ✅ | ✅ | ❌ |
| 代理自动检测（`Set-Proxy -Command auto`） | ✅ | ✅（可由参数跳过） | ❌ |
| Linux PATH 同步（`Sync-PathFromBash`） | ✅ | ✅ | ❌ |
| Starship/Zoxide/fnm/sccache 初始化 | ✅ | ❌ | ❌ |
| 别名/包装函数注册 | ✅ | ❌ | ❌ |
| `Show-MyProfileHelp` 完整信息段 | ✅ | ✅ | 降级（提示模式，不依赖模块） |

> 说明：
> - `Minimal` 目标是“保留基础功能、去掉开发增强”。
> - `UltraMinimal` 目标是“只保留会话最小可用能力，优先速度与稳定性”。

## Capabilities

### New Capabilities
- 新增“极简模式”开关与行为边界，面向 Codex/CI/沙盒/一次性脚本执行。

### Modified Capabilities
- 现有“精简模式”语义保持兼容；新增“极简模式”用于进一步减少初始化路径与副作用。

## Impact

- **修改文件**: `profile/profile.ps1`（必要时 `profile/profile_unix.ps1` 文档注释同步）
- **新增文档**: 本变更 proposal/design/tasks
- **行为影响**:
  - 普通交互 shell 行为不变
  - 极简模式下只保留最小能力，放弃开发增强特性换取启动速度和稳定性
