# 实施计划：Arch Linux Core 支持与旧目录归档

## 阶段 A：实现前合同

- [x] 读取 `trellis-before-dev` 及 `bash-scripts`、`pwsh-scripts`、`infra/linux-install-pipeline`、`infra/package-sources`、`infra/repository-archive` 相关规范。
- [x] 更新测试期望：Arch amd64 从 Partial/Blocked 转为 Full，并为 Arch package family 建立清单与 pacman 断言。
- [x] 保持 Debian/Ubuntu、WSL 与 ARM 现有测试作为回归边界。

## 阶段 B：Arch Stage 0

- [x] 扩展 `linux/00quickstart.sh`：按发行版族检查和安装 Debian/Arch 前置，保持 Direct 与 China/Auto 合同。
- [x] 扩展 `linux/02installPowerShell.sh`：支持 Arch 官方 tarball、本地包、SHA256 校验、稳定安装路径和安装后验证。
- [x] 更新 Bash fixture 与 Vitest，覆盖 Arch dry-run、前置缺失、非 Direct Blocked 和资产计划。

## 阶段 C：Arch Stage 1

- [x] 在 `config/install/linux-packages.psd1` 增加 Arch Core、Docker 与 DesktopFonts 清单。
- [x] 在 `linux/pwsh/LinuxInstall.psm1` 增加统一系统包分派与 pacman 实现，保留 apt 现有行为；使用单次 `pacman -Syu --needed` 避免部分升级。
- [x] 将 Arch amd64 支持级别提升为 Full。
- [x] 扩展 `06installFonts.ps1`、`07installProfileTools.ps1`、Docker 安装与 `99verifyInstall.ps1` 使用统一包接口。
- [x] 补充 Pester：pacman Preview、字体 Desktop/Server、Docker、验证 JSON 与退出码。

## 阶段 D：可选 yay

- [x] 新增 `linux/arch/installYay.sh`，实现帮助、参数校验、sudo 前置、幂等、临时目录、普通用户 makepkg 与 dry-run。
- [x] 增加 Bash/Vitest 测试，确保 dry-run 零写入并覆盖安装命令计划。
- [x] 不实现 fcitx5；在文档中标注其后续设计边界。

## 阶段 E：文档与规范

- [x] 更新 `linux/INSTALL.md` 和 `docs/INSTALL.md` 的支持矩阵与 Arch 使用方式。
- [x] 更新 `.trellis/spec/infra/linux-install-pipeline.md`：Arch Full、pacman、官方 PowerShell tarball、可选 yay 和测试合同。
- [x] 保留用户已移动的 `linux/docs/国内linux环境安装.md`，未扩大为文档重写任务。

## 阶段 F：冷归档 Batch 4

- [x] 先修复活动文档中 `linux/ubuntu/apply_config.sh` 的引用风险。
- [x] 对四个目录重新运行 `archive_project.py plan`，确认替代入口存在且无活动代码/测试/安装引用。
- [x] 获得用户对最终计划的明确批准后，以相同参数执行 `archive --execute`。
- [x] 不改写 `archive/linux/**` 中被移动文件正文。
- [x] 运行 `archive_project.py check`，检查 `archive/index.json` 四个稳定条目与 Git `R100` rename。

## 阶段 G：验证

- [x] `bash -n` 检查所有新增或修改的 Bash 入口。
- [x] `pnpm test:bash`（33 passed）。
- [x] `pnpm test:pwsh:all`（host 760 passed；Linux 757 passed；均 0 failed）。
- [x] `pnpm qa`（changed 模式通过；PowerShell 176 passed，workspace QA 通过；macOS 按规则跳过 Linux-only 子门禁）。
- [x] `python3 .agents/skills/project-archive/scripts/archive_project.py --repo-root "$(git rev-parse --show-toplevel)" check`
- [x] `git diff --check`
- [x] 检查 `git status --short`、`git diff --stat` 与 rename 识别；归档对象均为 `R100`，未处理任务外改动。

## 风险与回滚点

- Stage 0 会触及系统目录，测试必须通过 fixture、伪命令和 dry-run 完成，不在开发机真实安装 Arch 包。
- PowerShell tarball 安装路径和链接更新必须保持幂等；校验失败时不得覆盖现有可用版本。
- Docker 服务启用只在真实 Arch Full 且 daemon 不可用时执行；Preview 不调用 systemctl。
- 归档必须晚于替代能力验证；若归档检查失败，先反向移动失败单项并恢复索引，不扩大 archive 排除规则。
