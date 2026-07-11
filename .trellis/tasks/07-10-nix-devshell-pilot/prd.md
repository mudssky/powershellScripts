# Nix 开发环境试点

## Goal

在 Apple Silicon macOS 与 Ubuntu 24.04 WSL2 x86_64 上验证一个显式启用、可复现且可完整回退的 Nix flake 开发环境，为仓库构建、测试和脚本开发提供一致工具链，同时保持现有用户配置、平台安装流水线和全局软件安装链不变。

## Background

- 本任务是 `07-10-personal-config-nix-ansible` 的叶子任务，依赖已完成的网络源事务合同与统一安装编排器合同。
- Nix 首期只用于仓库级开发环境，不是 macOS/Linux Core 或 Full 安装预设的隐藏后端；现有 `install.ps1` 无参数兼容行为及显式 Preset 合同保持不变。[`.trellis/spec/infra/install-orchestrator.md:25`](../../spec/infra/install-orchestrator.md)
- 当前本机为 Apple Silicon macOS，已有 Node `24.14.1`、pnpm `10.33.0`、PowerShell `7.5.4`、Rust/Cargo `1.94.1`，尚未安装 Nix。现有原生工具链可作为试点前后的对照基线。
- Nix 官方文档将 macOS、Linux 和 WSL2 列为支持场景；原生 Windows 不在本试点范围。官方文档同时说明 flakes 仍是实验特性，因此必须显式启用并把锁文件、升级和回退行为纳入验证。

## Confirmed Facts

- 仓库 CI 使用 Node 24，并通过根 `package.json` 的 `packageManager` 固定 pnpm `10.33.0`。[`.github/workflows/test.yml:66`](../../../.github/workflows/test.yml) [`package.json:84`](../../../package.json)
- 根 QA 与开发命令直接依赖 `pwsh`、Node/pnpm 和 Cargo；PowerShell 测试依赖 Pester，Rust 用于运行仓内 `pwshfmt-rs`。[`package.json:10`](../../../package.json) [`package.json:13`](../../../package.json) [`package.json:28`](../../../package.json)
- `pwshfmt-rs` 使用 Rust 2024 edition，但仓库当前没有 `rust-toolchain` 文件；Rust 版本策略需要由本试点明确，而不能假定已有仓库级固定版本。[`projects/clis/pwshfmt-rs/Cargo.toml:1`](../../../projects/clis/pwshfmt-rs/Cargo.toml)
- Docker-backed Linux Pester 测试通过宿主 `docker compose` 运行，Nix dev shell 不能凭自身提供 Docker daemon。[`package.json:47`](../../../package.json)
- 当前 macOS 对照基线中，fnm 目录约 `2.7G`、rustup 目录约 `2.5G`、Cargo 目录约 `352M`、PowerShell 安装约 `199M`、项目 `node_modules` 约 `442M`、pnpm store 约 `707M`，`pwshfmt-rs/target` 约 `572M`。这些数字包含历史版本或缓存，不能直接等同于单个工具的最小安装体积，但可用于比较试点前后的净增量。
- Nix 使用独立 `/nix/store`，不会复用 fnm、rustup、Homebrew 或手工安装目录中的现有运行时；试点阶段的 Node、PowerShell、Rust 等通常会形成额外副本。Nix 可在自身 store 内通过内容寻址、垃圾回收和相同文件硬链接降低重复，但项目 `node_modules`、pnpm store 与 Rust `target` 构建产物仍单独存在。
- 现有 package source 规范把 Nix 标记为 `Unsupported`，直到存在可靠、结构化且可恢复的实现；禁止用 `nix-channel` 冒充 flake substituter，也禁止写入猜测性配置。[`.trellis/spec/infra/package-sources.md:61`](../../spec/infra/package-sources.md) [`.trellis/spec/infra/package-sources.md:92`](../../spec/infra/package-sources.md)
- source 的 `Direct` 模式必须零写入；`China` 必须保留原始快照并支持显式恢复；`Auto` 只允许临时修改并在结束时恢复。Nix source 接入必须遵守相同事务语义。[`.trellis/spec/infra/package-sources.md:53`](../../spec/infra/package-sources.md)
- macOS 与目标 WSL 均采用 multi-user Nix；daemon 会限制普通用户指定额外 binary cache。USTC source transaction 必须在提权上下文中 snapshot、修改和恢复系统级 `/etc/nix/nix.conf`，并按平台重启 daemon；禁止通过 `trusted-users` 扩大用户长期权限。

## Requirements

- 提供根目录 `flake.nix` 与提交到 Git 的 `flake.lock`，默认输出可通过 `nix develop` 进入。
- `flake.lock` 首期只允许人工执行 `nix flake update` 更新；不新增定时 workflow、Dependabot 或其他机器人更新。每次更新必须审阅 lock diff，并重新执行两平台核心验收。
- dev shell 首期只覆盖 `aarch64-darwin` 与 Ubuntu 24.04 WSL2 `x86_64-linux`；原生 Windows 继续使用现有 PowerShell 与平台包管理器链。
- dev shell 提供仓库开发所需的 PowerShell、Node 24、pnpm `10.33.0`、Rust/Cargo、Git 与经证据确认的必要构建 CLI；不把个人常用软件清单整体搬入 flake。
- Nix 只管理开发运行时与系统级 CLI；Node 项目依赖继续由根 `pnpm-lock.yaml` 管理，Rust crate 继续由 `projects/clis/pwshfmt-rs/Cargo.lock` 管理。首期不把 `node_modules`、pnpm store、Cargo registry 或 crate 构建产物预构建进 Nix store。
- pnpm 版本继续以根 `package.json#packageManager` 为唯一真源；flake 不维护相互独立的第二个 pnpm 版本常量。
- Rust 版本必须有明确且可审查的固定策略，并能构建 Rust 2024 edition 的 `pwshfmt-rs`。
- dev shell 隔离供应并固定 Pester `5.7.1`，通过 devshell 专属 `PSModulePath` 使用；不得写入、覆盖或优先级污染用户现有 PowerShell 模块目录，退出 dev shell 后恢复原模块解析行为。
- 只使用 `nix develop` 提供临时仓库环境，不引入 Home Manager、nix-darwin、NixOS 系统配置或 `nix profile install`。
- 不用 Nix 安装字体、GUI 应用、Profile、bash/zsh 配置、系统服务、Docker daemon 或原生 Windows 软件。
- Nix 必须由用户显式选择；根 `install.ps1 -Preset Core|Full`、平台编号脚本和无参数兼容入口不得静默切换到 Nix 后端。
- 首期只通过用户显式执行 `nix develop` 激活环境；不提交 `.envrc`，不集成 direnv 自动激活，也不在进入仓库目录时自动下载依赖或修改 PATH。
- flake 首期只声明 `aarch64-darwin` 与 `x86_64-linux`，并要求两个 system 都完成真实运行验证；`x86_64-darwin` 与 `aarch64-linux` 暂不声明支持，后续有真实环境时再扩展。
- 记录 Nix 首次安装、flakes 所需设置、进入与退出 dev shell、锁文件更新、垃圾回收、缓存占用查看及完整卸载方法。
- macOS 使用 Nix 官方 multi-user installer；Linux 真实验证环境固定为 `Ubuntu 24.04 WSL2 x86_64 + systemd`，同样使用官方 multi-user installer。未启用 systemd 的 WSL2 single-user `--no-daemon` 路径只记录兼容说明，不作为首期真实验收环境。首期不采用 Determinate Nix Installer。
- 卸载验收必须按安装模式分别检查 daemon/service、build users/group、shell profile 注入、系统与用户 Nix 状态目录以及 `/nix` store；不能只以 `nix` 命令不在 PATH 中作为完成依据。
- 安装前记录磁盘基线；首次实现 dev shell 后记录下载量、已实现 closure 大小、完整 `/nix/store` 大小、首次进入耗时、二次进入耗时，以及垃圾回收后的净磁盘增量。
- 垃圾回收后的 Nix 净磁盘增量以不超过 `10G` 为正常验收上限。`10G`～`20G` 仅表示机器容量可以承受，不代表方案默认合格；进入该区间必须先定位重复输入、历史 closure、源码构建或非必要工具并尝试裁剪，仍无法降到 `10G` 内时必须由用户单独批准例外。超过 `20G` 时停止试点扩展。
- 国内网络方案必须基于当前 Nix flake/substituter 与 trusted key 机制验证，不使用 chsrc 的 `nix-channel` 行为替代。
- 自定义 substituter 必须绑定对应公钥并可预览、应用、查看状态和恢复；不得静默覆盖用户已有的外部 Nix 配置。
- 真实 Nix source Apply、Status 与 Restore 必须使用一致的提权上下文；事务输出提供可执行的提权恢复命令，恢复后重启 daemon 并校验配置 hash。
- 国内 binary cache 默认顺序为 USTC 动态缓存优先、`cache.nixos.org` 官方源 fallback；不得把 USTC 配置写入 flake `nixConfig`，只能由可恢复的 source transaction 管理。TUNA 与 SJTUG 首期不进入共享默认值。
- Nix source adapter 必须同时覆盖隔离 fixture 测试与真实环境演练：Apple Silicon macOS 和 Ubuntu 24.04 WSL2 x86_64 各执行一次受事务保护的 Apply、`nix develop` 与 Restore，并比较恢复后的配置 hash。
- 退出 dev shell 后，原生 PATH、Node、pnpm、PowerShell、Rust/Cargo 与用户配置不得被持久修改。
- 交互式 dev shell 保留宿主 `HOME`、pnpm/Cargo 缓存、`SSH_AUTH_SOCK`、Git 凭据、代理与终端变量；同时必须保证 Node、pnpm、PowerShell、Pester、Rust/Cargo 等核心命令解析到 flake 锁定的工具或隔离模块，并记录实际命令路径。
- dev shell 的核心开发闭环必须支持 `pnpm install --frozen-lockfile`、`pnpm qa`、`pnpm test:pwsh:full:assertions` 和 `cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`。
- 宿主 Docker daemon 可用时追加执行 `pnpm test:pwsh:linux:full`；daemon 缺失时必须报告宿主前置条件，不得把它归类为 flake 或 dev shell 缺陷。

## Acceptance Criteria

- [ ] Apple Silicon macOS 可从未安装 Nix 的基线完成安装、进入 dev shell、执行约定验证命令、退出并完成卸载回退。
- [ ] `Ubuntu 24.04 WSL2 x86_64 + systemd` 可通过官方 multi-user installer 安装 Nix、进入同一 flake 的 dev shell 并执行约定验证命令。
- [ ] macOS 官方 multi-user 安装与 WSL2 对应的官方安装模式均有安装前 snapshot、安装后状态和逐项卸载验证记录。
- [ ] flake 只暴露 `aarch64-darwin` 与 `x86_64-linux` 的首期 dev shell 输出，且两个输出均有真实验证记录。
- [ ] `flake.lock` 固定 nixpkgs 输入；重复进入 dev shell 时核心工具版本符合约定，锁文件不会被隐式改写。
- [ ] `flake.lock` 只有在人工更新命令下变化；文档记录更新、diff 审阅与两平台回归流程。
- [ ] 未执行 `nix develop` 时仓库目录不会自动激活 Nix 环境；退出后 PATH 与 shell 状态恢复。
- [ ] dev shell 内 Node 为 24.x，pnpm 与 `package.json#packageManager` 一致，PowerShell、Cargo 和 Rust 编译器可用，`pwshfmt-rs` 可构建或运行。
- [ ] `pnpm install --frozen-lockfile` 与 Cargo locked dependency resolution 继续消费现有 lockfile；flake 不生成第二套项目依赖锁定或 vendoring 机制。
- [ ] dev shell 内 `Get-Module Pester -ListAvailable` 可解析固定的 `5.7.1` 隔离副本；退出后用户级 Pester 目录、版本和 `PSModulePath` 保持原状。
- [ ] Apple Silicon macOS 与 Ubuntu 24.04 WSL2 x86_64 的 dev shell 均可运行 `pnpm install --frozen-lockfile`、`pnpm qa`、`pnpm test:pwsh:full:assertions` 和 `cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`。
- [ ] 宿主 Docker 可用时追加运行 `pnpm test:pwsh:linux:full`；daemon 缺失时明确报告宿主前置条件，而不是 flake 或 dev shell 缺陷。
- [ ] 试点报告包含安装前后、首次进入、二次进入、dev shell closure、完整 store 与垃圾回收后的资源数据，并与预先批准的磁盘预算比较。
- [ ] 垃圾回收后的 Nix 净磁盘增量不超过 `10G`；`10G`～`20G` 只有在列出主要 closure、完成裁剪并获得用户例外批准后才可继续，超过 `20G` 必须停止。
- [ ] Direct 模式不修改 Nix source；China/Auto 的 substituter 与 trusted key 变更有 snapshot、状态、drift 防护和可执行 Restore。
- [ ] China/Auto 应用后 substituter 顺序为 USTC → `cache.nixos.org`，缓存对象必须通过有效 trusted key 验证；Restore 后不残留该顺序。
- [ ] Apple Silicon macOS 与 Ubuntu 24.04 WSL2 x86_64 均完成一次真实 Nix source Apply → `nix develop` → Restore 演练，Restore 后配置存在性、内容 hash 与权限回到试点前状态。
- [ ] 退出 dev shell 后原生工具版本与用户配置保持不变；删除 flake 文件或卸载 Nix 不影响现有安装流程。
- [ ] dev shell 内宿主 SSH、代理和包缓存仍可使用；核心工具路径与版本报告证明未误用 fnm、rustup、Homebrew 或用户级 Pester。
- [ ] 文档包含安装、日常使用、锁文件更新、缓存检查、垃圾回收、故障回退和完整卸载步骤。
- [ ] 实施前补齐并审阅 `design.md` 与 `implement.md`。

## Out Of Scope

- Home Manager、nix-darwin、NixOS、系统服务和用户主目录声明式管理。
- 原生 Windows 支持。
- 用 Nix 替代现有 Core/Full 安装流水线、Homebrew、apt、Scoop、Winget、Chocolatey 或 Cargo 用户软件清单。
- 由 dev shell 创建或管理 Docker daemon、GUI 应用、字体、Profile 或 shell rc。
- 默认自动化测试不修改真实系统 Nix 配置；真实 China/Auto Apply 只在已批准的 Phase 2 演练中执行。
