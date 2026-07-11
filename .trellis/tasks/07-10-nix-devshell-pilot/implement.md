# Nix 开发环境试点实施计划

## 0. 实施前检查

- [ ] 记录 `git status --short`，只处理 Nix 试点及其直接 source adapter、测试、规范和文档；不吸收父任务目录的其他未跟踪改动。
- [ ] 读取 `.trellis/spec/infra/package-sources.md`、相关 Bash/PowerShell 规范及本任务 research/design。
- [ ] 确认本机仍未安装 Nix，记录 Node、pnpm、PowerShell、Rust/Cargo、Pester 路径与版本基线。
- [ ] 记录 macOS 磁盘、`/nix` 存在性、launch daemon、build users/group、shell 配置与 `/etc/nix/nix.conf` 基线。
- [ ] 确认 Ubuntu 24.04 WSL2 x86_64 已启用 systemd，并准备相同基线采集。

## 1. 建立 Flake

- [ ] 新增根 `flake.nix`，只包含一个 nixpkgs input 和两个 system 输出，不引入 flake-utils、rust-overlay、Home Manager 或 nix-darwin。
- [ ] 新增 `nix/` helper，仅承载 Pester derivation、pnpm/Corepack wrapper 等不能清晰内联的逻辑。
- [ ] 使用 `nodejs_24`、PowerShell、Rust/Cargo/clippy/rustfmt、Git 和最小构建工具构造 dev shell。
- [ ] pnpm wrapper 从根 `package.json#packageManager` 解析版本与完整性，不复制 `10.33.0` 常量；首次调用才允许 Corepack 获取缺失版本。
- [ ] Pester derivation 固定 `5.7.1`、官方来源与 Nix hash，安装到只读模块目录。
- [ ] shell hook 只设置进程级 `PSModulePath`、Corepack cache 与遥测关闭等变量；不写 HOME 配置，不自动运行安装命令。
- [ ] 生成并提交 `flake.lock`，审阅只有预期 nixpkgs 输入。

## 2. Flake 静态与本机验证

- [ ] 运行 flake show/evaluation，确认只暴露 `aarch64-darwin` 与 `x86_64-linux` dev shell。
- [ ] 进入 macOS dev shell，记录 `command -v` 与版本：Node、pnpm、pwsh、git、rustc、cargo、clippy、rustfmt。
- [ ] 验证 pnpm 等于 `packageManager` 版本，Pester `5.7.1` 的首选 `ModuleBase` 位于 `/nix/store`。
- [ ] 退出 dev shell，确认宿主工具路径、版本和 `PSModulePath` 回到基线。
- [ ] 验证未提交 `.envrc`，普通 `cd` 不触发 Nix。

## 3. 实现 Nix Source Adapter

- [ ] 修改 `config/network/package-sources.json`：Nix target 使用 system scope adapter，声明 `/etc/nix/nix.conf`、USTC mirror、官方 fallback、probe 与正式 trusted key。
- [ ] 新增 `scripts/pwsh/misc/package-sources/adapters/NixAdapter.psm1`，所有公共函数补齐中文帮助、参数与返回值说明。
- [ ] 支持测试系统根、配置读取、当前状态、HTTPS cache probe、受控合并、Nix 配置解析校验、原子写入和时间戳 `.bak`。
- [ ] macOS 实现 launchd daemon restart；Linux 实现 systemd daemon restart；测试环境可显式跳过并模拟失败。
- [ ] 把 adapter 接入 PackageSources import、implemented list、resource path、apply、state 与结果 message。
- [ ] system scope Apply 前验证 root；rollback command 对 system target 输出可执行的提权命令。
- [ ] 禁止 adapter 修改 `trusted-users`、关闭签名校验、删除官方 fallback 或记录完整敏感配置。
- [ ] Apply 后读取 effective Nix config；失败时由事务恢复原文件并重启 daemon。

## 4. Adapter 测试

- [ ] Pester：Direct 零写入、Plan 可用、catalog 不再返回 Unsupported。
- [ ] Pester：USTC → official 顺序、官方 key、保留未知配置与注释、创建 `.bak`、原子写入。
- [ ] Pester：文件原本不存在、已是目标配置、重复 Apply、China active transaction 与重复 Restore。
- [ ] Pester：Auto 官方健康不写入、官方失败才应用、健康外部配置保留、不可用外部配置拒绝覆盖。
- [ ] Pester：非 root 真实 system path 返回 Blocked；临时 system root 不要求 root。
- [ ] Pester：daemon restart 成功/失败、Apply 后校验失败自动恢复、Restore 后 hash/权限/存在性一致。
- [ ] Pester：drift 阻断、Force 人工恢复、JSON stdout 单文档、manifest 不包含配置原文或 secret。

## 5. 文档与规范

- [ ] 新增项目级 Nix devshell 指南，包含官方安装、显式 `nix develop`、工具边界、核心命令、人工 lock 更新、缓存/GC、资源测量和完整卸载。
- [ ] 在 `docs/INSTALL.md` 与根 README 添加简短入口，明确 Nix 不属于 Core/Full 隐藏后端。
- [ ] 更新 `.trellis/spec/infra/package-sources.md`，把 Nix 从 Unsupported 改为 system transaction adapter 合同。
- [ ] 记录无 systemd WSL 的 single-user `--no-daemon` 兼容说明，但不声称已验证。
- [ ] 建立 macOS 与 WSL 实测报告，记录时间、平台、命令、版本、路径、closure、store、耗时、测试和卸载证据。

## 6. macOS 真实试点

- [ ] 使用官方 multi-user installer 安装 Nix，记录 installer 输出、daemon、build users/group、shell 注入与 `/nix` 状态。
- [ ] 运行 Direct Plan/Status，确认 `/etc/nix/nix.conf` hash 不变且 daemon 未重启。
- [ ] 提权执行 Nix China/Auto Apply，保存 transaction ID、backup、effective config 与 daemon 状态。
- [ ] 执行首次和二次 `nix develop`，记录下载量与耗时。
- [ ] 在 dev shell 执行核心工具检查和四条必测开发命令。
- [ ] 宿主 Docker daemon 可用时追加 Linux Pester；不可用时记录宿主前置条件。
- [ ] 提权 Restore source，确认 `/etc/nix/nix.conf` 存在性、权限、hash 与 daemon 状态恢复。
- [ ] 记录 closure、完整 store、GC/optimise 后净增量；超过 `10G` 先分析并裁剪。
- [ ] 按官方 multi-user 卸载清单完整卸载，打开新终端复核原生工具链和系统残留。

## 7. Ubuntu 24.04 WSL2 真实试点

- [ ] 确认 x86_64、Ubuntu 24.04、WSL2 与 systemd 状态并记录基线。
- [ ] 使用官方 multi-user installer 安装 Nix，验证 systemd `nix-daemon`。
- [ ] 重复 Direct、提权 Apply、首次/二次 `nix develop`、核心命令、四条必测开发命令与条件 Docker 测试。
- [ ] 提权 Restore source，确认配置、权限、hash 和 daemon 状态恢复。
- [ ] 记录 closure、store、GC 后净增量和主要差异。
- [ ] 按官方 Linux multi-user 清单卸载并检查 service、build users/group、shell 注入、用户状态和 `/nix` 残留。

## 8. 项目质量门禁

- [ ] 运行 Nix adapter 定向 Pester 测试。
- [ ] 运行 `pnpm qa` 并修复问题。
- [ ] 因涉及 PowerShell source adapter 与 Pester 测试，运行 `pnpm test:pwsh:all`。
- [ ] 若 Docker 本机不可用，至少运行 `pnpm test:pwsh:full`，并明确 Linux 覆盖依赖 WSL/CI。
- [ ] 分别在两个 dev shell 中复跑 `pnpm qa`、`pnpm test:pwsh:full:assertions` 与 Rust cargo test。
- [ ] 检查 `git diff --check`、`git status --short`、flake lock diff 和任务验收映射。

## 9. 回退点

- [ ] Flake 失败：删除新增 flake/helper，不修改现有安装入口。
- [ ] Pester/pnpm 固定失败：保留 Node/PowerShell/Rust 最小 shell，回到规划修正供应方式，不静默使用宿主版本冒充成功。
- [ ] Source Apply 失败：立即事务 Restore；Restore 失败时停止后续下载并保留 backup/manifest。
- [ ] 资源超过 `10G`：先移除非必要工具、重复输入与历史 closure；`10G`～`20G` 需用户例外批准，超过 `20G` 停止。
- [ ] 卸载残留：不宣布试点完成，逐项清理 daemon、users/group、shell 注入、state/cache 与 `/nix`。

## 10. 启动前审查

- [ ] PRD 已完成 convergence pass，无重复事实或已解决 Open Questions。
- [ ] 用户审阅并批准 `prd.md`、`design.md` 与 `implement.md`。
- [ ] 审批后运行 `task.py start 07-10-nix-devshell-pilot`，再进入实现阶段。
