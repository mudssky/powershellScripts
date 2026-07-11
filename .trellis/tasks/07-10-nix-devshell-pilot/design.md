# Nix 开发环境试点设计

## 目标与边界

本设计在根仓库增加显式 `nix develop` 开发环境，并把 Nix binary cache 接入现有 package source transaction。Nix 只负责仓库开发运行时，不接管平台安装流水线、用户配置、GUI、Profile、Docker daemon 或原生 Windows。

首期只支持并真实验证：

- `aarch64-darwin`：Apple Silicon macOS。
- `x86_64-linux`：Ubuntu 24.04 WSL2，systemd 已启用。

## 总体架构

```text
flake.nix + flake.lock
  ├─ devShells.aarch64-darwin.default
  └─ devShells.x86_64-linux.default
       ├─ nixpkgs 锁定的 Node / PowerShell / Rust / Git
       ├─ package.json 驱动的 pnpm wrapper
       └─ 固定源码与 hash 的 Pester 5.7.1 derivation

Switch-Mirrors.ps1 -Target nix
  └─ NixAdapter.psm1
       ├─ snapshot /etc/nix/nix.conf
       ├─ 写入 USTC → cache.nixos.org
       ├─ 使用既有官方签名信任链验证对象
       ├─ 重启 nix-daemon
       └─ Restore 原文件、权限与 hash，再重启 daemon
```

## Flake 结构

### 输入与输出

- 只引入一个 `nixpkgs` input，首期不引入 `flake-utils`、rust-overlay、Home Manager 或 nix-darwin，减少锁文件输入和重复 closure。
- `flake.lock` 固定 nixpkgs revision；人工执行 `nix flake update` 才允许更新。
- `flake.nix` 使用本地 `systems = [ "aarch64-darwin" "x86_64-linux" ]` 与小型 `forAllSystems` helper 生成输出。
- 默认输出只有 `devShells.<system>.default`；不声明未验证 system，也不创建 profile/package 安装输出。

### 工具链来源

| 工具 | 来源 | 固定策略 |
|---|---|---|
| Node.js | `nixpkgs.nodejs_24` | Node major 固定为 24，具体 patch 由 `flake.lock` 固定 |
| pnpm | Nix store 中的 Corepack wrapper | wrapper 读取根 `package.json#packageManager`，不得维护第二个 pnpm 版本常量 |
| PowerShell | `nixpkgs.powershell` | 具体版本由 `flake.lock` 固定；必须同时支持两目标 system |
| Pester | 独立 fixed-output derivation | 固定 `5.7.1` 与下载 hash，安装到只读 Nix store 模块目录 |
| Rust | `rustc`、`cargo`、`clippy`、`rustfmt` | 全部来自同一锁定 nixpkgs，不引入 rust-overlay |
| Git/基础构建工具 | nixpkgs | 只加入 QA 与构建真实需要的最小集合 |

### pnpm wrapper

- Corepack 与 Node 24 由 Nix 提供，wrapper 自身位于 `/nix/store/.../bin/pnpm`。
- wrapper 在仓库内调用 Corepack，由根 `package.json#packageManager` 选择 pnpm `10.33.0` 并校验其中的完整性信息。
- `COREPACK_HOME` 指向用户缓存目录，不在 `nix develop` 激活时自动下载；首次实际执行 pnpm 时才允许获取缺失版本。
- `command -v pnpm` 必须指向 Nix store wrapper，`pnpm --version` 必须等于 `packageManager` 声明版本。

### Pester derivation

- 从 PowerShell Gallery 或 Pester 官方发布源获取 `5.7.1`，实现时记录 URL 与 Nix hash。
- derivation 只解包模块到 `$out/share/powershell/Modules/Pester/5.7.1`，不运行 `Install-Module`，不写用户 HOME。
- dev shell 在现有 `PSModulePath` 前追加该模块根；不删除宿主模块路径。
- 验证不仅检查版本，还检查优先解析的 `ModuleBase` 位于 `/nix/store`。
- 当前 `pnpm qa` 的 PowerShell 格式化已由 `pwshfmt-rs` 接管，因此首期不把 PSScriptAnalyzer 纳入 closure；若真实验收发现直接依赖，再以证据追加。

## 环境继承

- 保留宿主 `HOME`、`SSH_AUTH_SOCK`、Git 凭据、代理、终端变量、pnpm store 和 Cargo cache，避免破坏日常开发。
- 核心工具通过 Nix package 顺序优先于 fnm、rustup、Homebrew 与用户级 PowerShell 模块。
- shell hook 只设置进程级变量，不修改 rc、Profile、Git 配置、npm/pnpm/Cargo 配置或用户模块目录。
- 不提交 `.envrc`；只有显式 `nix develop` 才激活环境。

## 项目依赖边界

- Node 依赖继续由根 `pnpm-lock.yaml` 与 `pnpm install --frozen-lockfile` 管理。
- Rust crate 继续由 `projects/clis/pwshfmt-rs/Cargo.lock` 管理。
- Nix 不 vendor `node_modules`、pnpm store、Cargo registry 或 Rust `target`。
- Docker CLI/daemon 不加入核心 closure；保留宿主 Docker 可见性，daemon 存在时追加集成测试。

## Nix Source Adapter

### Catalog

`config/network/package-sources.json` 中 `nix` target 改为真实 system adapter：

- platforms：`macos`、`linux`。
- phase：`Optional`。
- scope：`system`。
- resource：`/etc/nix/nix.conf`。
- mirror：`https://mirrors.ustc.edu.cn/nix-channels/store`。
- official fallback：`https://cache.nixos.org/`。
- trusted key：只使用正式文档确认的有效签名 key；不为镜像站添加未经证明的新信任根。

### 权限与状态

- Direct 仍为零写入、零重启。
- China/Auto 的真实 Apply、Status、Restore 在提权 PowerShell 进程中执行；不把当前用户加入 `trusted-users`。
- 默认测试通过 `POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT` 和独立 state root 映射到临时目录，不要求 root，也不重启真实 daemon。
- 系统 target 的 rollback command 必须包含明确的提权调用；transaction manifest 不记录配置原文或 secret。

### 配置写入

- Apply 前由通用 transaction snapshot `/etc/nix/nix.conf` 的存在性、内容、权限和 hash。
- adapter 只拥有 `substituters` 与必要的 `trusted-public-keys` 设置；其他行、注释和未知设置原样保留。
- 写入采用同目录临时文件、Nix 自身配置解析校验和原子替换；真实文件额外创建可读时间戳 `.bak` 备份。
- substituter 顺序固定为 USTC 在前、官方 cache 在后；禁止完全移除官方 fallback。
- 不设置 `trusted-users`，不启用 `require-sigs = false`，不接受未签名对象。

### daemon 生命周期

- macOS 使用 launchd 管理的 `org.nixos.nix-daemon`。
- Ubuntu WSL2 使用 systemd `nix-daemon`。
- Apply 写入成功但 daemon 重启或有效配置验证失败时，立即恢复 snapshot；恢复失败返回 `Blocked` 并保留事务证据。
- Restore 先执行 drift 校验，再恢复文件或删除原本不存在的文件，重启 daemon，并比较最终 hash、权限和存在性。

## 安装与卸载

### 安装

- macOS 使用 Nix 官方 multi-user installer。
- Ubuntu 24.04 WSL2 + systemd 使用 Nix 官方 multi-user installer。
- 安装前记录 `/nix`、daemon、build users/group、shell 注入、Nix 配置和磁盘基线。
- 首期不采用 Determinate installer，也不引入 Home Manager/nix-darwin。

### 卸载

卸载验证按官方 multi-user 清单执行并记录：

- 停止、禁用并移除 daemon service/launch daemon。
- 删除 Nix build users 与 group。
- 删除官方 installer 写入的 shell profile 引用。
- 清理系统与用户 Nix profile、cache、state、config。
- macOS 卸载 `/nix` APFS volume；WSL/Linux 删除 `/nix`。
- 新终端确认 `nix` 不在 PATH，原生 Node/pnpm/PowerShell/Rust 路径和版本回到基线。

## 资源测量

在同一文件系统口径下记录：

- 安装前可用空间和现有工具链基线。
- 官方 installer 完成后的 `/nix` 大小。
- 首次 `nix develop` 下载量、耗时与 realized closure。
- 二次 `nix develop` 耗时。
- `nix path-info --closure-size` 的 dev shell closure。
- 完整 store 大小，以及 garbage collection/optimise 后净增量。

正常验收上限为 GC 后净增量 `10G`。`10G`～`20G` 必须先分析主要 closure 并裁剪，仍需保留时由用户单独批准；超过 `20G` 停止试点扩展。

## 验证分层

### 每个平台必测

- flake evaluation 与锁文件稳定性。
- 核心工具版本和 `command -v`/模块路径。
- `pnpm install --frozen-lockfile`。
- `pnpm qa`。
- `pnpm test:pwsh:full:assertions`。
- `cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`。
- 退出 dev shell 后宿主路径与版本恢复。

### 条件测试

- 宿主 Docker daemon 可用时运行 `pnpm test:pwsh:linux:full`。
- daemon 不可用时记录为宿主前置条件，不算 flake 缺陷。

### Source 真实演练

macOS 与 WSL2 各完成一次：

1. Direct Plan/Status，确认零写入。
2. 提权 Apply USTC → official fallback。
3. 验证有效 Nix 配置与签名下载。
4. 进入 dev shell 完成至少一个真实 substitute/download。
5. 提权 Status，确认无 drift。
6. 提权 Restore，确认文件、权限、hash 与 daemon 状态恢复。

## 回退策略

- flake 层：删除 `flake.nix`、`flake.lock` 与 `nix/` helper 即恢复无 Nix 仓库状态。
- source 层：使用 transaction Restore；有 drift 时停止，除非人工审阅后显式 Force。
- 安装层：按官方 multi-user uninstall 清单完整卸载。
- 原有 `install.ps1`、Core/Full 预设和平台叶子不调用 Nix，因此 Nix 失败不阻断现有安装链。

## 主要取舍

- 不使用 flake-utils/rust-overlay：减少输入与维护成本，但 system 列表和 Rust 工具由本仓显式维护。
- Corepack 驱动 pnpm：保持 `packageManager` 单一真源，但首次 pnpm 调用仍可能访问网络。
- Pester 自建 derivation：实现真正隔离，但需要维护固定 URL/hash。
- 修改系统 `nix.conf`：multi-user daemon 下行为可靠，但真实演练需要 sudo 和 daemon restart。
- 保留宿主缓存与凭据：日常体验更好，但验收必须额外证明核心工具解析到 Nix store。
