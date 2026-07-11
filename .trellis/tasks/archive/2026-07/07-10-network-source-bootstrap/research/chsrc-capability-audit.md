# chsrc 能力审计

## 版本与资料

- Context7 在 2026-07-11 已收录官方项目 `/rubymetric/chsrc`；当前文档显示命令格式为 `chsrc <command> [options] [target] [mirror]`，作用域参数为 `-scope=project|user|system`。
- 本机安装版本仍为 `0.2.2`，未执行系统升级。Homebrew 元数据给出的稳定版为 `0.2.5`，上游发布日期为 2026-03-25。
- 为避免修改本机安装，审计在临时目录下载 `v0.2.5` 源码包并校验 Homebrew 公式 SHA-256 `4fc7ccbdea9c18aaa06b1efc80cc8a1941e38060b8495c67c947a09d2a0dfeac`，随后本地构建临时二进制。
- 上游支持 Homebrew、Scoop、WinGet、AUR 和多平台安装方式；默认 unattended 路径仍应优先使用平台包管理器或已校验资产，不直接 pipe 远程 installer。
- 0.2.5 选项必须放在 command 之后，例如 `chsrc list -no-color brew`；`chsrc -no-color list brew` 返回参数错误，adapter 不得自行交换参数顺序。

## 已验证目标

临时构建的 `chsrc 0.2.5` 可列出 brew、npm、pnpm、Python/pip/uv、Rust/Cargo、rustup、Go、winget、Ubuntu、Arch、Docker、Nix 等目标。

能力并不一致：

- npm、pnpm、pip、uv、Rust/Cargo、rustup、Go、winget、Ubuntu 具有 Get/Reset；具体 scope 与写入方式仍不同。
- Homebrew 支持 Get 但不支持 Reset，并直接向 shell rc 追加环境变量；rustup 虽支持 Reset，但实现同样向已有 rc 追加环境变量，均与仓库 shell 托管边界冲突。
- Cargo 0.2.5 会直接覆写 `~/.cargo/config.toml`，不能在未做结构化 TOML 合并时用于真实 HOME。
- uv 会直接写 `~/.config/uv/uv.toml`；在无法证明保留现有字段前，不直接用于真实 HOME。
- Arch、Docker 缺少 Reset；Nix 缺少 Get/Reset 且仍围绕 `nix-channel`，不能代表 flake/substituter 的完整方案。
- Docker 已有仓库自维护的 JSON 结构化写入、探活和备份逻辑，直接改用 chsrc 会丢失现有能力。

## 0.2.5 Adapter 决策

| Target | 0.2.5 证据 | 首期 adapter |
|---|---|---|
| brew | Get；用户级；写 shell rc；无 Reset | managed-env，通过隔离 HOME 提取白名单环境变量 |
| rustup | Get/Reset；用户级；向已有 rc 追加环境变量 | managed-env，通过隔离 HOME 提取白名单环境变量 |
| npm | Get/Reset；项目级和用户级 | chsrc apply + 原生命令 snapshot/restore |
| pnpm | Get/Reset；项目级和用户级 | chsrc apply + 原生命令 snapshot/restore；工具缺失时 Deferred |
| pip | Get/Reset；用户级 | chsrc apply + `pip config` snapshot/restore |
| go | Get/Reset；用户级 | chsrc apply + `go env` snapshot/restore |
| uv | Get/Reset；会写 TOML | 首期 Unsupported，等待结构化 TOML 合并 |
| rust/Cargo | Get/Reset；会覆写 Cargo TOML | 首期 Unsupported，等待结构化 TOML 合并 |
| winget | Get/Reset；用户级；移除并重建 source | Windows 专用 adapter，先导出 source 再应用 |
| Ubuntu/Debian | 系统级；需要 root | chsrc system adapter + 已知系统文件 snapshot |
| Arch | 系统级；无 Reset；需要 root | chsrc system adapter + mirrorlist snapshot |
| Docker | 无 Reset；实际 dry-run 仍要求权限 | 仓库 Docker adapter |
| Nix | 无 Get/Reset；依赖 nix-channel | 仅保留扩展接口 |

## 0.2.5 Dry-run 证据

- `chsrc set -dry -scope=user brew first`：写入 `.zshrc`，内容包含四个 Homebrew 环境变量；源 URL 由 chsrc recipe 生成。
- `chsrc set -dry -scope=user npm first`：调用 `npm config set registry ...`。
- `chsrc set -dry -scope=user pnpm first`：调用 `pnpm config -g set registry ...`。
- `chsrc set -dry -scope=user pip first`：调用 `python3 -m pip config --user set global.index-url ...`。
- `chsrc set -dry -scope=user uv first`：备份并写 `~/.config/uv/uv.toml`。
- `chsrc set -dry -scope=user rust first`：显示覆写 `~/.cargo/config.toml`。
- `chsrc set -dry -scope=user go first`：调用 `go env -w GO111MODULE=on` 与 `go env -w GOPROXY=...`。
- `chsrc set -dry -scope=user winget first`：移除并重新添加 winget source，必须由专用 adapter 先捕获完整原状态。
- Ubuntu、Arch、Docker 在非提权环境下即使 dry-run 也返回权限错误；测试不能依赖本机 dry-run 代替 fixture。

## 设计结论

- chsrc 是主要 adapter，不是唯一 adapter，也不是 source 状态真源。
- 仓库必须在 chsrc 外层记录变更前状态、目标版本、配置路径与恢复动作。
- 对会直接写 shell rc、缺少 reset、只打印配置或无法覆盖当前工具机制的 target，使用专用 adapter。
- chsrc 尚未安装时，由极小的原生 bootstrap adapter 先配置平台包管理器；安装 chsrc 后再接管公共语言生态目标。
- chsrc 的镜像列表优先于仓库复制 URL；只有 bootstrap 或不受支持 target 的少量地址集中放入配置文件。
