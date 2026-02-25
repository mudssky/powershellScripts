## 1. Linux 脚本拆分与重命名

- [x] 1.1 从 `linux/02installHomeBrew.sh` 中拆出 Homebrew 安装部分，创建 `linux/01installHomeBrew.sh`（仅 Homebrew 安装 + 环境变量配置）
- [x] 1.2 从 `linux/02installHomeBrew.sh` 中拆出 PowerShell 安装部分，创建 `linux/02installPowerShell.sh`（本地 deb + fallback 逻辑）
- [x] 1.3 创建 `linux/03deployShellConfig.sh`，调用 `shell/deploy.sh`
- [x] 1.4 将 `linux/03installApps.ps1` 重命名为 `linux/04installApps.ps1`
- [x] 1.5 删除原 `linux/02installHomeBrew.sh`（已拆分完成）

## 2. macOS 脚本拆分与重命名

- [x] 2.1 从 `macos/01install.sh` 中拆出 Homebrew 安装部分，创建 `macos/01installHomeBrew.sh`
- [x] 2.2 从 `macos/01install.sh` 中拆出 PowerShell 安装部分，创建 `macos/02installPowerShell.sh`
- [x] 2.3 创建 `macos/03deployShellConfig.sh`，调用 `shell/deploy.sh` + symlink `.zshrc`
- [x] 2.4 将 `macos/02installApp.ps1` 重命名为 `macos/04installApps.ps1`
- [x] 2.5 创建 `macos/05deployHammerspoon.sh`，调用 `hammerspoon/load_scripts.zsh`
- [x] 2.6 删除原 `macos/01install.sh`（已拆分完成）

## 3. 跨平台安装文档与引用更新

- [x] 3.1 创建 `docs/INSTALL.md`，包含两阶段结构：第一阶段引导到平台 INSTALL.md，第二阶段描述 PowerShell 层安装步骤（install.ps1、install.ps1 -installApp、installModules.ps1）
- [x] 3.2 创建 `linux/INSTALL.md`，包含步骤 0-4 的完整 manifest（含仓库拉取指引），末尾引导回 `docs/INSTALL.md`
- [x] 3.3 创建 `macos/INSTALL.md`，包含步骤 0-5 的完整 manifest（步骤 0 为手动 clone 指引），末尾引导回 `docs/INSTALL.md`
- [x] 3.4 更新根目录 `README.md`，添加指向 `docs/INSTALL.md` 的安装指南引用
- [x] 3.5 更新 `install.ps1` 中 `linux/01manage-shell-snippet.sh` 路径为 `shell/deploy.sh`

## 4. 清理与验证

- [x] 4.1 全局搜索旧文件名引用（`02installHomeBrew.sh`、`01install.sh`、`03installApps.ps1`、`02installApp.ps1`），更新相关文档和脚本中的引用
- [x] 4.2 验证 Linux 脚本链：`00quickstart.sh` → `01` → `02` → `03` → `04` 可按顺序执行（dry-run 或语法检查）
- [x] 4.3 验证 macOS 脚本链：`01` → `02` → `03` → `04` → `05` 编号连续且脚本存在
