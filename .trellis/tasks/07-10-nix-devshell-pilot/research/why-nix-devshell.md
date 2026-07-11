# 为什么在本仓库试点 Nix Devshell

## 当前决策

本任务已完成需求与技术规划，但暂缓实施，继续保持 `planning`。暂缓不代表否决 Nix；后续只有在需要验证 macOS 与 WSL 的统一开发环境时再恢复任务。

## Nix 在本仓库中的用途

Nix 的目标不是替代现有项目依赖管理，也不是接管整台机器，而是把仓库使用的跨语言开发工具链封装成一个显式进入、可复现且可回退的项目环境。

当前工具链由多个独立入口管理：

| 当前方式 | Nix devshell 试点 |
|---|---|
| fnm 管理 Node | flake 固定 Node 24 |
| Corepack 或全局环境管理 pnpm | 根 `package.json#packageManager` 固定 pnpm `10.33.0` |
| Homebrew 或手工安装 PowerShell | 锁定 nixpkgs 提供的 PowerShell |
| 用户模块目录安装 Pester | devshell 隔离提供 Pester `5.7.1` |
| rustup 管理 Rust | 锁定 Rust、Cargo、clippy 与 rustfmt |
| 每台机器分别准备工具 | 显式执行 `nix develop` 进入同一套环境 |

## 主要优势

### macOS 与 WSL 工具版本一致

Node、pnpm、PowerShell、Pester 和 Rust/Cargo 由同一份 flake 与 lock 文件约束，减少本机可运行但另一平台失败的版本漂移。

### 新机器恢复路径集中

安装 Nix、克隆仓库并执行 `nix develop` 后即可获得约定运行时，不需要分别配置 fnm、rustup、PowerShell 和 Pester。

### 工具链可随 Git 回退

`flake.lock` 跟随仓库提交。工具链更新引发回归时，可以通过回退提交恢复此前的 nixpkgs revision 与工具版本。

### 不接管原生环境

只有显式进入 devshell 后才优先使用 Nix 工具。退出后继续使用原有 fnm、rustup、PowerShell、Homebrew、SSH、代理与用户缓存。

### 跨语言入口统一

本仓库同时使用 Node、PowerShell、Rust 和 Git。Nix 的价值是统一运行时入口，而不是再创建一套 Node 或 Rust 项目依赖锁定机制。

## 明确不解决的内容

- Node 项目依赖继续由 `pnpm-lock.yaml` 管理。
- Rust crate 继续由 `Cargo.lock` 管理。
- Docker daemon 继续由宿主系统提供。
- 不管理 GUI、字体、Profile、shell rc 或系统设置。
- 不覆盖原生 Windows，只覆盖 Apple Silicon macOS 与 Ubuntu 24.04 WSL2 x86_64。
- 不替代现有 `install.ps1`、Core/Full 预设和平台包管理器链。

## 成本与风险

- 预计增加约 `3G`～`10G` 的 Nix 净磁盘占用；正常验收上限为垃圾回收后 `10G`。
- macOS multi-user Nix 涉及 daemon、build users、shell 注入和 `/nix` volume，完整卸载比普通 CLI 复杂。
- 国内 binary cache 的可靠应用需要事务化修改系统级 `/etc/nix/nix.conf` 并重启 daemon。
- 需要维护 flake、Pester derivation、source adapter 和两平台验证证据。
- Nix 官方资料仍将 flakes 标记为实验特性，并提示整仓复制、输入重复、依赖预取和实现问题等成本。
- 如果主要只在一台已经配置完成的 Mac 上开发，Nix 的边际收益较低。

## 采用判定

本仓库适合把 Nix 作为可撤销试点，不适合直接让 Nix 接管用户配置或整机软件。

恢复任务后应通过以下问题决定是否正式采用：

- macOS 与 WSL 是否确实能通过一条 `nix develop` 获得一致工具链。
- 四条核心开发命令是否都能在两平台运行。
- 退出 devshell 和完整卸载后是否没有持久污染。
- 国内网络下 binary cache 是否可靠、可签名验证且可恢复。
- 垃圾回收后的净磁盘增量是否不超过 `10G`。
- 日常维护成本是否低于分别维护 fnm、rustup、PowerShell/Pester 安装的成本。

任一关键条件不满足，尤其是磁盘超过 `10G`、卸载残留或维护复杂度明显高于现有方案时，应判定试点不值得继续，而不是为了已经投入的规划成本强行采用。

## 官方资料依据

- Nix declarative shell：<https://nix.dev/tutorials/first-steps/declarative-shell>
- Nix flakes 概念与限制：<https://nix.dev/concepts/flakes>
- Nix 安装与支持平台：<https://nix.dev/install-nix>
