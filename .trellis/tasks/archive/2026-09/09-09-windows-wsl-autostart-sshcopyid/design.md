# Design：Windows WSL 自启接线与 SSHCopyID

## 架构与边界

本任务不新增任何环境恢复逻辑——`windows/wsl/WslSshAccess.psm1` 已实现全部机制（Initialize/Refresh/Verify、AtStartup+S4U 计划任务、portproxy 2222→2223、TCP relay keepalive）。本任务只做三件事：**接入流水线**、**补清单条目**、**补验证视图**。

```
steps.psd1 (windows 10 login-items: Supported=true)
   └─> windows/10deployWslAutostart.ps1   [新叶子，薄封装]
          └─> windows/wsl/Initialize-WslSshAccess.ps1
                 └─> WslSshAccess.psm1（机制层，不改或最小改动）

profile/installer/apps-config.json (winget 段 + axeprpr.SSHCopyID)
   └─> 既有 Install-PackageManagerApps / Test-PackageManagerAppCatalog 链路

windows/99verifyInstall.ps1
   └─> 新增 login-items 检查（复用 WslSshAccess verify + psutils 应用检测）
```

## 关键设计决策

1. **叶子薄封装，逻辑留在机制层**：`10deployWslAutostart.ps1` 只做参数解析/默认值推断/前置检查/调用 Initialize/结果转译。机制逻辑一律复用 `WslSshAccess.psm1`，避免第二份实现漂移。
2. **步骤位选 10 login-items**：计划任务本质是 startup item，语义吻合；windows 10 当前 `Supported=$false`，激活不影响其他平台；09 已被 AutoHotkey 占用。
3. **前置不足 → Blocked（10）**：无 WSL 发行版（`wsl -l -q` 空/失败）或 build < 22621 时，叶子返回 Blocked 并说明缺失项，遵循仓库"不静默回退"约定。目标机（已有 WSL Ubuntu）不受影响。
4. **参数默认值推断**：DistroName 缺省取 `wsl -l -q` 首个发行版；WindowsUser 缺省取当前用户；ListenPort/GuestPort 沿用 Initialize 现有默认 2222/2223；PublicKey 等参数透传。所有默认可被显式参数覆盖。
5. **SSHCopyID 落 winget 段**：工具为 winget 独有包（axeprpr.SSHCopyID）；条目字段对齐 apps-config 既有 winget 条目结构（autohotkey/eartrumpet 为样例），`supportOs: ["Windows"]`，安装命令带 `-e --accept-package-agreements --accept-source-agreements`。安装步骤归属跟随既有 winget 应用的选中链路（实现时确认 05/08 的标签选择，保持一致）。
6. **verify 只读复用**：99 的新检查优先调用 `WslSshAccess.psm1` 的 verify（任务存在且 Trigger/Principal 匹配、portproxy 监听）与 psutils `Test-ApplicationInstalled`（ssh-copy-id），保持单文档 JSON 契约。

## 兼容与迁移

- 已手动执行过 INSTALL.md 143-167 命令的机器（含用户实机）：Initialize 幂等，流水线重跑收敛；计划任务同名覆盖。
- WSL 尚未安装的新机：步骤 Blocked，不阻断后续独立步骤（编排器既有行为）。
- CI（Linux 容器）：Windows 叶子仅跑 WhatIf/Pester mock 路径，与 WindowsInstallPipeline.Tests.ps1 既有模式一致。

## 权衡与回滚

- 权衡：受管自动化 vs 手动入口并存（INSTALL.md 保留手动命令，等价非弃用）。
- 回滚点：steps.psd1 的 windows 10 条目改回 `Supported=$false` 即可摘除步骤；apps-config 条目独立可删；叶子文件独立可删。三者互不纠缠。
