# 环境安装指南

本文档是项目的安装总入口。新机流程分为 Stage 0 与 Stage 1；无参数 `install.ps1` 仍保留为仓库工具准备入口，不会隐式执行完整装机。

## Stage 0：平台基础环境

根据你的操作系统，先完成对应的平台安装：

- **Linux**: 参考 [linux/INSTALL.md](../linux/INSTALL.md)
- **macOS**: 参考 [macos/INSTALL.md](../macos/INSTALL.md)

Stage 0 负责获得 Git、平台包管理器、仓库与 PowerShell 7。PowerShell 7 可用后，平台入口把控制权交给根 Stage 1；它不维护 Core/Full 步骤列表。

## 仓库工具准备（兼容入口）

```powershell
pwsh ./install.ps1
```

无参数调用保持原行为：配置 PATH、同步 `bin` shim、构建 Bash/Node 工具，并执行仓库开发环境准备。现有 `pnpm pwsh:install` 与 `pnpm scripts:install` 继续使用该入口。

## Stage 1：统一安装编排器

只有显式传入 `-Preset Core|Full` 才进入 Stage 1：

```powershell
# 查看当前平台的步骤、支持状态和未来叶子路径
pwsh ./install.ps1 -ListSteps
pwsh ./install.ps1 -ListSteps -OutputFormat Json

# 预览或执行预设
pwsh ./install.ps1 -Preset Core -WhatIf
pwsh ./install.ps1 -Preset Full -NetworkMode Direct

# 精准重跑，不自动展开依赖
pwsh ./install.ps1 -Preset Core -Step core-cli

# 假定前序步骤已完成，从指定步骤继续
pwsh ./install.ps1 -Preset Core -FromStep core-cli

# 排除步骤；依赖被排除时，下游返回 Blocked
pwsh ./install.ps1 -Preset Full -SkipStep full-apps
```

Stage 1 固定顺序为 `03 sources`、`04 shell`、`05 core-cli`、`06 fonts`、`07 profile-tools`、`08 full-apps`、`09 platform-automation`、`10 login-items`、`11 desktop-integration`、`99 verify`。Core 选择 `03`～`07` 与 `99`；Full 追加 `08`～`11`。

步骤串行执行。失败只阻断依赖步骤，独立步骤和可执行的 `verify` 继续。平台不支持的步骤为 `Skipped`；声明支持但真实叶子尚未接入时为 `Blocked`。退出码为：成功/预览 0、执行失败 1、参数错误 2、仅 Blocked 10。

### 网络模式与恢复

- `Direct`：默认模式，不创建 source 事务。
- `China`：保留事务，汇总输出 transaction ID 与 Restore 命令。
- `Auto`：需要镜像时创建临时事务，编排器在成功、失败或异常路径的 `finally` 中 Restore。
- Auto Restore 失败时整体至少为 `Blocked`；若安装步骤已经 `Failed`，原始失败仍保持最高优先级。

`-OutputFormat Json` 的 stdout 只包含一个 JSON document，叶子日志不会混入标准输出。`-Unattended` 与 `-NonInteractive` 互斥；`-WhatIf` 不创建 source 事务，也不写用户配置。

当前 macOS、Linux/WSL 与 Windows 的新编号真实叶子由各平台任务逐步接入。叶子缺失时返回 Blocked 是首期预期行为，不会回退旧脚本伪报完整成功。

## 旧应用安装入口

```powershell
pwsh ./install.ps1 -installApp
```

该入口迁移期内继续调用旧平台应用安装脚本并输出弃用提示，不映射为 Full，也不能与 Preset 或步骤参数组合。

## 单独安装 PowerShell 模块

- **脚本**: `profile/installer/installModules.ps1`
- **执行方式**: `pwsh ./profile/installer/installModules.ps1`
- **前置条件**: 步骤 1 完成
- **可跳过**: 是
- **说明**: 安装 Pester 等 PowerShell 模块
