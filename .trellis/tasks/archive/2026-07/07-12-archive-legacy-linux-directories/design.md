# 技术设计：Arch Linux Core 支持与旧目录归档

## 1. 总体边界

本任务在同一条现役 Linux `00` 至 `99` 流水线内增加 Arch Linux amd64 Core 支持，不创建第二套 Arch 编排器。旧 `linux/archlinux/**` 只作为实现证据，能力吸收后与 `linux/ubuntu`、`linux/wsl2`、`linux/cloundsever` 一起进入根冷归档。

交付分成两个有顺序依赖的阶段：

1. 先完成并验证 Arch 现役能力，确保替代入口真实存在。
2. 再执行 Batch 4 冷归档，修复活动引用并更新 `archive/index.json`。

不拆子任务：归档 `linux/archlinux` 必须依赖同一变更中的替代实现，拆开会产生旧入口已移走但新入口尚不可用的中间状态。

## 2. 平台与支持矩阵

- `arch + amd64` 从 `Partial` 提升为 `Full`。
- `debian/ubuntu + amd64` 保持 `Full`。
- ARM 与未知发行版保持 `Blocked`。
- WSL 客体规则不变；Arch WSL 若平台探测成立，仍遵循 WSL 字体默认 Server 和客体配置合同。

对应更新：

- `linux/pwsh/LinuxInstall.psm1` 平台能力模型。
- `.trellis/spec/infra/linux-install-pipeline.md` 与 `linux/INSTALL.md` 支持矩阵。
- Pester 平台模型及叶子测试。

## 3. Stage 0

### 3.1 系统前置

`linux/00quickstart.sh` 根据 `LI_DISTRIBUTION_FAMILY` 分派前置检查与安装：

- Debian：保留 `apt-get` 路径。
- Arch：用 `pacman` 检查并安装 `base-devel`、`ca-certificates`、`curl`、`git`。

Direct 模式允许执行官方系统包命令。China/Auto 在缺少前置且没有可恢复 Stage 0 adapter 时返回 10，不静默使用官方源。

### 3.2 PowerShell

`linux/02installPowerShell.sh` 保持统一入口：

- Debian 使用官方 `.deb`。
- Arch 使用 PowerShell GitHub 最新稳定版 `linux-x64.tar.gz`。
- 下载对应官方 SHA256 清单并在解包前校验资产。
- Arch 安装到稳定的系统目录，通过原子替换或版本目录加稳定链接暴露 `pwsh`；安装后执行 PowerShell 7 版本验证。
- `--package` 接受与当前发行版匹配的本地 `.deb` 或 `.tar.gz`；格式不匹配返回参数错误。
- dry-run 只输出计划，不访问网络或写系统。

Linuxbrew 继续复用 `linux/01installHomeBrew.sh`，旧 `archlinux/installer/homebrew.sh` 不保留活动实现。

## 4. Stage 1 包管理

### 4.1 声明式清单

`config/install/linux-packages.psd1` 新增 `arch` family：

- `CoreSystem`：Arch Core 所需系统包。
- `Docker`：`docker` 与 Compose 包候选。
- `DesktopFonts`：`fontconfig`、Noto CJK 与 Nerd Font 包。

包名只存在于清单，不散落在叶子脚本。

### 4.2 通用安装函数

在 `LinuxInstall.psm1` 中引入按发行版族分派的系统包安装接口，Debian 内部继续调用 apt，Arch 内部调用 pacman。调用方 `06`、`07` 和 Docker 安装逻辑消费统一接口，避免复制整段叶子流程。

pacman 合同：

- 使用 `--needed` 保持幂等。
- 非交互执行使用 `--noconfirm`，但不绕过 sudo 前置合同。
- Preview 输出稳定命令，不探测或修改本机。
- 包安装失败返回结构化 `Failed`，权限不足按现有 sudo 规则返回 `Blocked`。

### 4.3 Docker

继续以 `docker info` 判断实际可用性。Arch 缺少 Docker 时从声明式包清单安装，使用 systemd 启动/启用 daemon，并复用当前用户组与重新登录提示逻辑。WSL 客体仍先处理 `/etc/wsl.conf`，不得从 Linux 脚本执行宿主 `wsl --shutdown`。

## 5. 字体与可选 AUR

`06installFonts.ps1` 对 Arch 使用相同的 Auto/Desktop/Server 合同：

- Server 与 WSL Auto 跳过。
- Desktop 安装清单字体并执行 `fc-cache -f`。

新增 `linux/arch/installYay.sh` 作为显式可选入口：

- 不进入 Core/Full 步骤图。
- 支持 `--dry-run`、`--unattended`、`--non-interactive`。
- 已存在 yay 时幂等退出。
- 使用 `mktemp` 克隆 AUR 仓库，以普通用户运行 `makepkg`；只通过 pacman 准备受控前置。
- 不用固定工作目录，不污染当前目录，不保留构建临时文件。

fcitx5 不在本期实现。旧说明随 `linux/archlinux` 归档，后续若实现必须新增独立桌面集成设计，不能恢复 `~/.pam_environment` 手工注释方案。

## 6. 验证与文档

- `99verifyInstall.ps1` 对 Arch Full 输出真实检查，不再结构化 Blocked。
- Bash/Vitest 覆盖 Arch Stage 0、PowerShell tarball计划、China/Auto Blocked、yay dry-run 与幂等路径。
- Pester 覆盖 Arch Full、包清单、pacman Preview、字体、Docker 与验证汇总。
- `linux/INSTALL.md` 说明 Arch Core 支持、Desktop 字体和可选 yay。
- 更新 Linux 流水线 Trellis spec，避免后续实现仍按“Arch Partial”回退。

## 7. 冷归档

使用 `project-archive` 工具执行 Batch 4：

- `linux/archlinux` -> `archive/linux/archlinux`
- `linux/ubuntu` -> `archive/linux/ubuntu`
- `linux/wsl2` -> `archive/linux/wsl2`
- `linux/cloundsever` -> `archive/linux/cloundsever`

执行前更新活动文档中对 `linux/ubuntu/apply_config.sh` 的历史链接，指向归档路径或移除其作为现役风格示例的表述。移动时不改写被归档文件正文，以保留 Git rename 识别。

回滚方式：对单项反向 `git mv`，删除对应 `archive/index.json` 条目，再运行归档检查和项目门禁。

