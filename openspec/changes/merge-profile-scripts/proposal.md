## Why

`profile.ps1`（Windows）和 `profile_unix.ps1`（Linux/macOS）之间存在约 70% 的代码重复——`Set-AliasProfile`、`Initialize-Environment`、`Show-MyProfileHelp`、工具初始化、`z` 懒加载等逻辑几乎完全相同。真正的平台差异仅约 25-30 行（~10%）。这导致每次修改共享逻辑时需要同步两个文件，极易遗漏（事实上 `Show-MyProfileHelp` 两版已经不一致，Unix 版缺少函数别名和持久变量显示；Unix 版未加载 `wrapper.ps1`）。

## What Changes

- 将 `profile.ps1` 和 `profile_unix.ps1` 的共享逻辑合并为统一的 `profile.ps1`，通过 `$IsWindows`/`$IsLinux`/`$IsMacOS` 条件分支处理平台差异
- 将 `profile_unix.ps1` 改为薄 shim，仅转发到 `profile.ps1`，保持向后兼容
- 统一使用 `Set-PowerShellProfile` 函数方式处理 LoadProfile 逻辑，替代 Windows 版的内联 param 方式
- 合并 `Show-MyProfileHelp` 为完整版（包含函数别名、持久变量显示）
- 统一加载 `wrapper.ps1`（当前 Unix 版缺失）
- 统一保留加载耗时统计（当前 Unix 版缺失）
- 合并工具初始化表（starship/zoxide 通用，sccache 仅 Windows，fnm 仅 Unix）

## Capabilities

### New Capabilities

- `unified-profile`: 统一的跨平台 PowerShell Profile 加载机制，通过单一入口文件 + 平台条件分支消除代码重复

### Modified Capabilities

（无现有 specs）

## Impact

- **修改文件**: `profile/profile.ps1`（重写为统一入口）、`profile/profile_unix.ps1`（改为薄 shim）
- **向后兼容**: 两个文件路径均保留可用，已有的 `$PROFILE` 引用不受影响
- **功能增强**: Unix 平台将获得之前缺失的 `wrapper.ps1` 函数（`yaz`、`Add-CondaEnv`）、完整的 `Show-MyProfileHelp`、加载耗时统计
- **依赖**: 无新增依赖，所有依赖（`psutils`、`loadModule.ps1`、`wrapper.ps1`、`user_aliases.ps1`）均已存在
