# 审计并整理旧 Linux 环境目录

## 目标

整理 `linux/` 下旧平台目录：把 Arch Linux 中仍有价值的安装意图升级为符合当前流水线契约的现役实现，并将被替代、失去活动入口或仅剩历史参考价值的旧实现纳入可追溯冷归档，避免新旧入口并列造成误用。

## 背景与已确认事实

- 当前 Linux 安装真源是 `linux/00quickstart.sh`、`linux/01` 至 `linux/08`、`linux/99verifyInstall.ps1` 及 `linux/INSTALL.md`。
- `linux/INSTALL.md` 明确首期完整支持 Ubuntu/Debian 与 Ubuntu/Debian WSL 客体；Arch 与 ARM 只识别并返回 Blocked，不提供完整安装支持。
- 已归档任务 `07-10-linux-wsl-install-pipeline` 判定 `linux/ubuntu/**`、`linux/archlinux/**`、`linux/wsl2/**` 为待独立归档处理的历史实现，新流水线不再引用它们。
- `linux/wsl/wsl.conf` 已接管 WSL 客体配置；Windows 宿主 `.wslconfig` 已迁到 `windows/wsl/`。
- `linux/wsl2/deprecated/proxy.sh` 已由 `shell/shared.d/proxy.sh` 替代。
- `linux/wsl2/startRedis.sh` 仅执行 `sudo service redis-server start`，无仓内活动引用；现役容器入口支持 `redis` 服务。
- `linux/cloundsever/container.ps1` 只是依次调用现役 `scripts/pwsh/devops/start-container.ps1` 启动若干服务，无仓内调用者；其编排清单可作为历史记录归档。
- 仓库冷归档采用根目录镜像路径 `archive/<原路径>`，并以 `archive/index.json` 为唯一索引真源。
- 任务创建前工作树为 clean；规划期间用户将 `linux/国内linux环境安装.md` 移到 `linux/docs/国内linux环境安装.md`，该改动予以保留并作为现有文档路径处理。
- 四个候选目录尚未进入 `archive/index.json`；Batch 4 只读计划均能生成镜像目标。

## 需求

- R1：逐文件审计 `linux/archlinux`，将仍有价值的 Arch 安装能力纳入当前 Linux 安装体系，不保留质量不足的平行旧入口。
- R1.1：Arch Linux 首期支持 `amd64`，并达到当前 Core 流水线的基本能力对齐：Stage 0、pacman、PowerShell、source、Shell 配置、Core CLI、Profile 工具、Docker 与只读验证。
- R1.2：Arch 桌面字体为显式 Desktop 能力，不进入默认 Core；服务器环境不得隐式安装桌面包。
- R1.3：默认 Core 不依赖 yay 或 AUR；Arch Stage 0 使用微软官方 PowerShell Linux 发布产物，系统包通过 pacman 安装。
- R1.4：yay 作为显式可选能力，安装过程使用临时构建目录并遵循幂等、非交互和 dry-run 契约；旧 `installer/yay.sh` 仅保留于冷归档。
- R1.5：本期把 Arch Desktop 字体接入现有 `06installFonts.ps1`；默认 Core/Server 保持跳过。
- R1.6：本期不自动配置 fcitx5 输入法；旧 `installer/IME.sh` 冷归档，并在规划或文档中记录后续需单独处理 Wayland/X11、桌面环境与重新登录语义。
- R1.7：yay 可选能力使用独立入口 `linux/arch/installYay.sh`，支持 dry-run、无人值守和严格非交互模式；不扩展根 `install.ps1` 的跨平台参数。
- R1.8：Arch PowerShell 使用 GitHub 最新稳定版官方 `linux-x64.tar.gz`，下载后校验官方 SHA256；显式本地包参数同时接受 Debian `.deb` 与 Arch `.tar.gz`。
- R1.9：China/Auto 在 Stage 0 没有可恢复下载 adapter 时，不静默直连；要求用户提供本地包或预装 PowerShell 7。
- R2：逐目录审计 `linux/cloundsever`、`linux/ubuntu`、`linux/wsl2`，确认活动引用、替代入口及残余独立价值。
- R3：只归档已失效、已被替代或仅供历史参考的对象；仍有活动入口或尚无合理替代的能力不得直接归档。
- R4：归档目标保持原路径镜像，不重分类、不删除历史内容，也不在移动提交中改写归档文件正文。
- R5：所有归档对象写入 `archive/index.json`，记录原因和替代入口或“仅供历史参考”说明。
- R6：执行物理归档前先展示只读计划，并取得用户对候选范围的明确批准。
- R7：整理完成后不得留下指向已归档旧路径的有效安装、测试、部署或文档入口。

## 验收标准

- [ ] `linux/archlinux/**` 每个旧文件均有“升级吸收”或“冷归档”的明确处置结论。
- [ ] Arch Linux amd64 可通过当前 `00` 至 `99` 编排体系完成 Core 安装和只读验证，并遵循统一参数、幂等、错误处理、dry-run/WhatIf 与退出码契约。
- [ ] 默认 Core 不安装输入法或桌面字体；显式 Desktop 路径可独立选择相关能力。
- [ ] Arch `-Environment Desktop` 使用声明式包清单安装字体并刷新 font cache；Auto/Server 行为与现有合同一致。
- [ ] 未启用可选 AUR 能力时，Arch Core 不克隆 AUR 仓库、不安装 yay，也不依赖社区 PowerShell 包。
- [ ] Arch PowerShell 下载资产经过官方 SHA256 校验；已有 PowerShell 7 时不重复下载或安装。
- [ ] 其余三个候选目录均有基于文件内容、仓内引用与替代关系的明确处置结论。
- [ ] 获批准的对象通过归档工具迁移到对应 `archive/linux/**` 镜像路径。
- [ ] `archive/index.json` 对每个归档对象包含原因及替代说明。
- [ ] `project-archive check` 通过，活动引用检查无未处理风险。
- [ ] 按项目规范完成适用的质量门禁，并确认 Git rename 与最终 diff 符合预期。
- [ ] 未获批准或仍有活动价值的文件保持原位。

## 范围外

- 不要求 Arch 与 Ubuntu/Debian 使用完全相同的软件包名称；要求其 Core 能力和行为合同基本对齐。
- 不在本期实现 fcitx5 或其他 Linux 输入法自动配置。
- 不保留仅为兼容旧目录结构而存在的转发脚本，除非存在已确认的外部使用场景。
- 不顺带整理 `linux/` 下未列入本次候选的其他文件或目录。
