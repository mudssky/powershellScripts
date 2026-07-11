# 合并 Profile 脚本任务

## 1. 准备工作

- [x] 1.1 在 `profile.ps1` 顶部添加 `$IsWindows` 兼容性检查（PowerShell 5.1 回退）
- [x] 1.2 统一 `param()` 块：合并两个文件的参数定义，采用 `$LoadProfile` switch + `$AliasDescPrefix` string

## 2. 合并 Initialize-Environment

- [x] 2.1 合并通用逻辑：env.ps1 加载、Set-Proxy、UTF8 编码、PSReadLine Tab 补全
- [x] 2.2 添加 Linux 平台分支：`Sync-PathFromBash`、Linuxbrew PATH 检测
- [x] 2.3 合并工具初始化表：starship（通用）、zoxide（通用）、sccache（仅 Windows）、fnm（仅 Unix）
- [x] 2.4 合并工具未安装提示：Windows 用 choco/scoop/winget，Unix 用 brew
- [x] 2.5 合并 Minimal 模式、SkipTools 系列开关逻辑
- [x] 2.6 合并 z 函数懒加载逻辑

## 3. 合并 Set-AliasProfile

- [x] 3.1 统一 `Set-AliasProfile` 函数（两版逻辑基本一致，以 Windows 版为准）

## 4. 合并 Show-MyProfileHelp

- [x] 4.1 以 Windows 版（完整版）为基准合并，包含：自定义别名、函数别名、函数包装、核心管理函数、关键环境变量、用户级持久环境变量

## 5. 统一 LoadProfile 逻辑

- [x] 5.1 将 `profile.ps1` 的内联 LoadProfile 逻辑替换为 `Set-PowerShellProfile` 函数（保留备份功能）
- [x] 5.2 统一主执行逻辑：调用 `Initialize-Environment` + 条件调用 `Set-PowerShellProfile`

## 6. 统一加载 wrapper.ps1

- [x] 6.1 确保 `wrapper.ps1` 在所有平台加载（当前 Unix 版缺失）

## 7. 保留加载耗时统计

- [x] 7.1 确保合并后的脚本包含加载耗时统计逻辑（当前 Unix 版缺失）

## 8. profile_unix.ps1 改为薄 shim

- [x] 8.1 将 `profile_unix.ps1` 替换为薄 shim，透传所有参数到 `profile.ps1`

## 9. 验证

- [x] 9.1 在 Linux 环境下通过 `pwsh -NoProfile -Command ". ./profile/profile.ps1"` 验证加载无报错
- [x] 9.2 在 Linux 环境下通过 `pwsh -NoProfile -Command ". ./profile/profile_unix.ps1"` 验证 shim 转发正常
- [x] 9.3 运行 `Invoke-ScriptAnalyzer` 检查合并后的 `profile.ps1` 无严重警告
