# 网络与镜像源准备

## Goal

为 macOS、Windows、WSL/Linux 与 Nix 试点提供统一、可预览、可恢复的网络源准备步骤：网络状况良好时保持官方源，需要国内镜像时在正式安装前集中完成换源，使后续字体、CLI、运行时和仓库工具安装能够连续执行。

## Background

- 仓库已有 `scripts/pwsh/misc/Switch-Mirrors.ps1`，但首期只管理 Docker registry mirror，不能覆盖安装链使用的 Homebrew、winget、npm/pnpm、PyPI、Cargo 或系统包源。
- Stage 0 尚未获得 Homebrew、PowerShell 或 chsrc，不能依赖 chsrc 解决自身下载问题；初始包管理器和 PowerShell bootstrap 需要极少量、集中管理的镜像或代理例外。
- macOS、Windows、Linux/WSL、统一编排器和 Nix 试点均依赖本任务提供共享 source engine；平台编号脚本只负责传参和展示结果，不各自维护镜像地址或恢复逻辑。
- chsrc 的版本与 target 能力审计记录在 `research/chsrc-capability-audit.md`；其中的本机输出是设计证据，不是永久 API 契约。

## Requirements

### 网络策略

- 统一入口将网络策略建模为 `Direct`、`China` 与 `Auto`；preview 是独立执行选项，不与网络模式混为一组。
- 未传网络模式时使用 `Direct`：不测速、不换源、不创建事务，也不重置用户已有自定义 source。
- `China` 在正式安装前集中应用国内镜像，持久保留到显式 `Restore`；重复应用必须复用原事务和最初 snapshot。
- `Auto` 先检查当前 source：未受本仓管理的自定义 source 若可用则原样保留；官方或默认 source 连续探测失败时才创建临时镜像事务，并记录触发原因。
- `Auto` 事务在流水线成功、失败或可捕获的中断清理阶段恢复原配置；发现上次异常退出留下的 orphan transaction 时，必须先恢复或返回 `Blocked`。
- 正式安装前只确定一次 source，后续步骤复用该结果；工具安装后才出现的 target 通过 `Ensure` 补应用既有事务意图，不重新随机测速。
- `China` 镜像不可用时返回失败或 `Blocked`，不得静默切回官方源并声称国内源已生效；`Auto` 镜像也不可用时先恢复原配置，再阻止依赖网络的后续步骤误报成功。

### Adapter 与所有权

- `Switch-Mirrors.ps1` 和共享模块负责策略、target catalog、事务、状态、adapter 调用和结构化输出；各平台 `03configureSources.*` 由对应平台流水线任务实现为薄包装。
- 优先通过 chsrc 或包管理器自身的 source/config 接口换源，镜像 URL 不得写入字体、CLI、Profile、GUI 应用等叶子安装脚本。
- chsrc 必须包在仓库适配层之后：执行前检查版本、target、`get/reset/local` 能力和 dry-run 行为，不能假设所有 target 具有相同语义。
- chsrc 不支持、不可逆、只输出手工配置或会直接改写 shell rc 的 target 使用专用 adapter；例外地址集中维护在统一配置中。
- Homebrew 与 rustup 不允许由 chsrc 直接向 `~/.zshrc`、`~/.bashrc` 追加内容；需要持久化的环境变量写入受管本机 env 文件，并由仓库 shell snippet 加载。
- Docker 保留现有 `/v2/` 探活和结构化 JSON 写入能力，迁入统一事务层，不再由 chsrc 重复管理。
- Nix 在本任务只定义 flake/substituter adapter 接口和事务格式，具体实现与真实验证由 `07-10-nix-devshell-pilot` 完成。

### Stage 0、状态与安全

- Stage 0 只允许为获得 Git、平台包管理器、PowerShell 与 chsrc 使用最小网络例外；POSIX 与 Windows PowerShell 5.1 均需有不依赖 PowerShell 7/chsrc 的 bootstrap helper。
- 进入 Stage 1 后立即交给统一 source engine，后续脚本不得继续携带 bootstrap 镜像逻辑。
- 变更任何全局或用户级 source 前，记录目标、原值、配置路径、工具版本、时间与修改前后 hash；恢复只能撤销本仓库实际改动。
- snapshot 必须使用受限权限保存，manifest 和日志不得包含 token、完整认证配置或 secret 环境变量。
- 状态与 manifest 使用原子写入和进程级互斥，避免并发安装或中断留下部分 JSON；发生外部 drift 时默认拒绝覆盖并返回 `Blocked`。
- 统一入口支持 `Plan`、`Apply`、`Ensure`、`Status` 与 `Restore`；重复 Apply 幂等，Restore 后重新读取 source 验证结果。
- 文本输出供人工使用，JSON 输出供 Stage 0/统一编排器消费；至少包含 target、选择原因、adapter、实际 source、持久性、验证结果、事务 ID 和回滚入口。
- 只允许 HTTPS 镜像，不允许关闭 TLS 校验，也不允许在 unattended 默认路径中直接 pipe 未固定、未校验的远程 installer 执行。

### 首期平台范围

- macOS：Homebrew，以及实际安装链使用的 npm/pnpm、PyPI/uv、Cargo/rustup、Go 源。
- Windows：winget，以及实际安装链使用的 npm/pnpm、PyPI/uv、Cargo/rustup、Go 源；Scoop、Chocolatey 和 PowerShell Gallery 需先验证是否存在可靠 source adapter。
- WSL/Linux：Ubuntu/Debian、Arch 等实际支持发行版的系统源，以及公共语言生态源；不得强行统一不同发行版的配置文件。
- Nix：保留 adapter 扩展点，不能把 chsrc 的 `nix-channel` 行为当作 `nix develop` 的完整镜像方案。
- Docker：迁移现有功能和兼容参数，默认地址改由统一配置维护。
- Scoop、Chocolatey、PowerShell Gallery 或未识别 Linux 发行版在能力未经验证时只能报告 `Unsupported`/`Direct`，不得写入猜测性配置。

## Technical Notes

- 当前 macOS 安装的是 `chsrc 0.2.2`，Homebrew 元数据在 2026-07-10 显示稳定版 `0.2.5`；实施前需要针对最终选择的稳定版本重新执行 target list 与 dry-run 审计。
- 本机审计显示 npm、pnpm、pip、uv、Go、winget 等有较明确的原生命令；brew、rustup 会修改 rc，Cargo 仅输出手工 TOML，Arch、Docker、Nix 的 reset 或现代用法不完整。
- Context7 在 2026-07-10 未检索到 chsrc 官方条目；版本边界以实际二进制行为和上游发布资料为准。

## Acceptance Criteria

- [x] 网络良好且选择官方源时，安装链不修改任何 package source。
- [x] 未传网络参数时等价于 `Direct`；`China` 与 `Auto` 必须由用户显式选择。
- [x] China 重跑幂等且显式 Restore 可恢复应用前状态；Auto 在正常结束、失败和可捕获中断后不留下镜像配置。
- [x] Auto 不覆盖健康的、未受本仓管理的自定义 source；orphan transaction 和 drift 均不会被静默覆盖。
- [x] 选择国内镜像时，在包安装开始前完成受支持 target 的集中换源并通过只读检查确认生效。
- [x] chsrc 与专用 adapter 的选择规则有证据、有版本边界，并覆盖 macOS、Windows、WSL/Linux 和 Nix 的差异。
- [x] 所有持久化变更都可预览、可追踪、可重复执行，并能只恢复本仓库造成的变更。
- [x] Stage 0 的镜像例外数量最小且集中维护；叶子安装脚本不包含各自的镜像 URL。
- [x] 共享入口可输出稳定 JSON，平台 `03` 与统一编排器可据此汇总并阻止依赖失败 source 的安装步骤。
- [x] 核心策略、事务、恢复和 adapter 行为有确定性自动化测试；真实镜像测速仅作为显式诊断，不进入默认 QA。
- [x] 现有 Docker 参数保持兼容，Docker 200/401、不可达、dry-run 与恢复行为无回归。
- [x] 最终采用的稳定 chsrc 版本已重新完成 capability/dry-run 审计，支持矩阵与实际实现一致。

## Out of Scope

- 搭建或维护私人镜像站。
- 将代理配置与镜像源视为同一机制；本地代理可以作为 Stage 0 的另一种网络通道，但不替代 source 状态管理。
- 在本任务安装字体、CLI、Profile、GUI 应用或 Nix 开发工具链。
- 创建 macOS、Windows、Linux/WSL 的编号安装脚本；对应平台任务只消费本任务定义的入口。
