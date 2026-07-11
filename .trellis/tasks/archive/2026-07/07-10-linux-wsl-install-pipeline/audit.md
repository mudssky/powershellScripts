# Linux WSL 安装步骤审计

## 结论

现有 Linux 主链不能直接接入统一编排器。主要问题不是缺少脚本数量，而是 Stage 0 与应用安装混合、包管理器职责重叠、镜像 URL 散落，以及 WSL 宿主配置与客体配置位于同一目录。

可复用资产已经足够：根编排器拥有步骤图，package source 引擎拥有事务，`apps-config.json` 拥有 Linuxbrew CLI，`shell/deploy.sh` 拥有 shell 配置同步，Profile 与构建入口也已跨平台。Linux 实现应以薄叶子和共享平台探测补齐缺口。

## 当前入口审计

| 入口 | 证据 | 问题 | 目标 |
|---|---|---|---|
| `linux/00quickstart.sh` | `:5-9` 无条件 apt 安装 gh 并进入登录；`:22` 把路径当命令执行；`:36` 使用完整 `gh repo clone` | 不能无人值守，依赖 GitHub 登录，存在直接失败语句，不支持 repo URL/目录/Preset/NetworkMode | 原路径重写为 Stage 0，使用 Git shallow clone 并移交根 Stage 1 |
| `linux/01installHomeBrew.sh` | `:16-17` 内嵌清华镜像；`:20` 引号内 `~` 不展开；`:43-49` 直接修改 `.bashrc` | 绕过 source 事务和 shell 部署合同，失败路径与幂等不稳定 | 原路径重写为 Linuxbrew Stage 0 叶子，镜像只通过 helper 注入 |
| `linux/02installPowerShell.sh` | `:15` 通过 `ls` 组装数组；`:35-40` 直接 dpkg/apt；`:63-73` 回退旧 Ubuntu 脚本 | 没有架构、版本、参数和预览合同；失败时可能打印 Warning 后成功结束 | 原路径重写为 amd64 PowerShell 7 叶子，支持本地 deb 和明确 Blocked |
| `linux/03deployShellConfig.sh` | `:12` 修改仓库脚本执行位；`:13` 不传 shell、preview 或交互参数 | 与统一编号冲突，包装层有额外副作用 | 新增 `04deployShellConfig.sh`；旧入口仅保留弃用薄包装 |
| `linux/04installApps.ps1` | `:7-10` 只按 `linuxserver` 过滤；`:15-17` 硬编码 npm 镜像；`:24-25` 直接写 `.bashrc`；`:43` 指向不存在的 Docker 文件名 | CLI、Node、Cargo、Docker 和 shell 修改混在一起，无法形成 Core/Full 或可靠退出码 | 拆为 05/07/08；旧入口仅作弃用兼容 |

## 发行版资产

| 范围 | 可复用部分 | 风险与处置 |
|---|---|---|
| `linux/ubuntu/functions.sh`、`installEnv.sh` | 记录了历史软件意图 | 同时使用 apt、brew、nvm、bun、pyenv、curl installer 和直接 rc 写入，不作为新流水线实现源 |
| `linux/ubuntu/installer/install_pwsh.sh` | GitHub release deb 安装思路 | 硬编码 `amd64`，解析 latest API，无临时目录、参数和非交互合同；由 02 统一替代 |
| `linux/ubuntu/installer/installDocker.sh` | Docker 缺失时安装的意图 | `get.docker.com --mirror Aliyun` 绕过 source catalog，且不能区分 Docker Desktop 集成；由 07 统一替代 |
| `linux/archlinux/01install.sh`、`02install.ps1` | pacman/yay/Homebrew 的历史清单 | 没有幂等、错误或预设合同；本期只用于确认 Arch 必须独立分流，不进入完整支持 |
| `linux/archlinux/installer/font.sh` | 原生包与 `fc-cache` 方案 | 可作为桌面字体包研究输入，不直接由默认服务器/WSL 流水线调用 |

## WSL 边界审计

- `linux/wsl2/wsl.conf:1-17` 是发行版客体配置，可迁入新的 `linux/wsl/` 所有权边界。
- `linux/wsl2/.wslconfig:1-30` 是 Windows 宿主全局 VM 配置，不属于本任务。
- `linux/wsl2/loadWslConfig.ps1:4-7` 写 `%UserProfile%/.wslconfig` 并执行 `wsl --shutdown`，必须留给 Windows 流水线处理。
- `linux/wsl2/installer/installPwsh.sh:4-30` 与公共 Linux 02 重复，且结束时直接启动交互式 `pwsh`，不应继续作为客体入口。
- `psutils/modules/docker.psm1` 已有 Windows 到 WSL Docker Engine wrapper，并优先保留可用 Docker Desktop；Linux 侧应以同样的“实际 daemon 可用”语义判断是否安装客体 Engine。

## 现有合同与缺口

- `config/install/steps.psd1` 已声明 Linux 03～08 与 99 的未来路径；09～11 已正确标记为不支持。
- `profile/installer/apps-config.json` 已为 Linux 提供 `core + cli` 和 `terminal-extras` 条目，05/08 无需创建第二份 CLI 清单。
- `psutils/modules/install.psm1` 已提供标签校验、纯选择和结构化安装结果，可直接复用。
- `config/network/package-sources.json` 已有 `ubuntu`、`debian`、`arch` system target，但 `brew` 当前仅声明 macOS，Linuxbrew 接入前必须扩展平台并补测试。
- 根编排器只向 sources 传 NetworkMode/TransactionId，向普通叶子传 Preset；因此 Linux 03 必须一次完成 Stage 1 source 计划，其他叶子不能私自选择镜像。
- 根编排器把叶子退出 0 归一为 Succeeded；动态字体/空清单跳过应作为叶子内部结果和 99 验证状态，不引入新的退出码。

## 迁移处置

- `00quickstart.sh`、`01installHomeBrew.sh`、`02installPowerShell.sh` 保留路径并重写为正式 Stage 0 叶子，Git 历史继续可追溯。
- `03deployShellConfig.sh`、`04installApps.ps1` 不再拥有业务逻辑，只在需要兼容弃用入口时转发到新编号叶子。
- `linux/ubuntu/**`、`linux/archlinux/**`、`linux/wsl2/**` 的历史文件不在本任务中批量移动；新文档和编排器不再引用它们，后续由根 `archive/` 批次处理。
