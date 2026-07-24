# Nix Devshell 使用指南

本仓库提供**可选**的 `nix develop` 开发环境，用于固定 Node / pnpm / PowerShell / Pester / Rust 工具链。

**不属于** `install.ps1` Core/Full 预设，也不接管宿主 Profile、Docker 或包管理器。

## 平台

| 系统 | 状态 |
|---|---|
| `x86_64-linux` | 已在本仓库试点验证 |
| `aarch64-darwin` | flake 已声明输出；**macOS 实测本轮跳过** |
| 无 systemd 的 WSL | 未验证；官方 multi-user 安装依赖 daemon |

## 安装 Nix（Linux multi-user）

```bash
# 官方 installer（网络差时请设置代理）
export https_proxy=http://HOST:PORT
sh <(curl -L https://nixos.org/nix/install) --daemon

# 启用 flakes（用户或系统）
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

新开终端后应能运行 `nix --version`。

## 进入开发环境

```bash
# 推荐：非 login shell，避免宿主 fnm/rustup 抢 PATH
nix develop -c bash --noprofile --norc

# 或直接跑命令
nix develop -c bash --noprofile --norc -c 'node -v && pnpm -v && pwsh -v'
```

进入后：

- `node` / `pnpm` / `pwsh` / `rustc` / `cargo` 应位于 `/nix/store/...`
- `pnpm` 版本来自根 `package.json#packageManager`（Corepack）
- `Pester 5.7.1` 通过 `PSModulePath` 前缀提供（宿主模块路径仍可能被 PowerShell 扫描到）

退出后宿主工具链恢复。

## 国内 binary cache

通过仓库统一 package source 事务（需 root）：

```powershell
# 预览（零写入）
./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Plan -Mode China -Target nix

# 应用 USTC → cache.nixos.org
sudo ./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Apply -Mode China -Target nix

# 恢复
sudo ./scripts/pwsh/misc/Switch-Mirrors.ps1 -Action Restore -TransactionId <id>
```

约束：

- 只改 `/etc/nix/nix.conf` 的 `substituters` 与 `trusted-public-keys`
- 必须保留官方 `https://cache.nixos.org/` 与官方公钥
- 不设置 `require-sigs = false`，不改 `trusted-users`

## 锁文件更新

```bash
nix flake update          # 人工更新 nixpkgs
git diff flake.lock       # 审阅
nix develop -c true       # 回归进入
```

禁止把 substituter 永久写进 `flake.nix` 的 `nixConfig` 影响所有用户。

## 资源与 GC

```bash
du -sh /nix/store
nix store gc
nix store optimise
```

试点验收口径：GC 后净增量宜 ≤ 10G。

## 卸载（Linux multi-user 概要）

按 [Nix 官方卸载说明](https://nix.dev/manual/nix/stable/installation/uninstall) 执行，至少包括：

1. `sudo systemctl stop nix-daemon.socket nix-daemon.service`
2. 删除 build users/group、`/nix`、shell 注入与 profile
3. 清理 `~/.nix-*`、`~/.local/state/nix`、`/etc/nix`

卸载后打开新终端确认 `command -v nix` 为空，宿主 Node/pnpm/PowerShell/Rust 回到基线。

## 相关文件

- `flake.nix` / `flake.lock`
- `nix/pester.nix` / `nix/pnpm-wrapper.nix`
- `scripts/pwsh/misc/package-sources/adapters/NixAdapter.psm1`
- `.trellis/tasks/07-10-nix-devshell-pilot/research/linux-pilot-report.md`
