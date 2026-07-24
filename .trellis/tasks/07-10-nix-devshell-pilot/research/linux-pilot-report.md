# Linux Nix Devshell 试点报告

- 日期：2026-07-24
- 主机：`server` / Ubuntu 22.04.5 LTS x86_64 / systemd running（**非** WSL）
- 代理：`http://192.168.21.108:7890`（官方 cache 直连不稳时使用）
- macOS：`aarch64-darwin` **本轮跳过实测**（flake 输出保留）

## 基线（安装前）

见 `linux-baseline.txt`：

- Node v24.11.0（fnm）
- pnpm 10.33.0
- PowerShell 7.5.3（`/usr/bin/pwsh`）
- rustc/cargo 1.92.0（rustup）
- `/nix` 不存在

## 安装

- 官方 multi-user installer Nix **2.35.1**
- 因网络中断，改为本地解压 tarball 后执行 `install --daemon --yes`
- `nix-daemon` active；installer 将代理写入 `nix-daemon.service.d/override.conf`
- `/etc/nix/nix.conf` 启用 `experimental-features = nix-command flakes`

## Flake

- `flake.nix` inputs：`nixpkgs` → `nixos-unstable`（需要 `nodejs_24`；24.11 无该属性）
- 输出：`devShells.aarch64-darwin.default`、`devShells.x86_64-linux.default`
- 工具：Node 24.18.0、pnpm wrapper（Corepack + packageManager）、PowerShell 7.6.3、Rust 1.97.0、Pester 5.7.1 derivation、git

## `nix develop` 验证（x86_64-linux）

命令：

```bash
nix develop -c bash --noprofile --norc -c '...'
```

结果：

| 工具 | 路径前缀 | 版本 |
|---|---|---|
| node | `/nix/store/...-nodejs-24.18.0` | v24.18.0 |
| pnpm | `/nix/store/...-pnpm` | 10.33.0（= packageManager） |
| pwsh | `/nix/store/...-powershell-7.6.3` | 7.6.3 |
| rustc/cargo | `/nix/store/...` | 1.97.0 |
| Pester | `/nix/store/...-pester-5.7.1/.../Pester/5.7.1` | 5.7.1（同时仍可见用户模块副本） |

注意：`bash -lc` 会加载宿主 profile，导致 fnm/rustup 抢 PATH；文档要求 `--noprofile --norc`。

退出后宿主：`fnm node 24.11.0`、`rustc 1.92.0`、`/usr/bin/pwsh` 恢复。

## Source Adapter

- catalog `nix`：`adapter=nix`、`scope=system`、`resource=/etc/nix/nix.conf`
- `NixAdapter.psm1`：探活、合并 substituters（USTC → cache.nixos.org）、保留未知键、时间戳 `.bak`、daemon 重启钩子
- 测试根 `POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT` 下：首次 Changed=true，二次 Changed=false
- 非 root 真实路径：Blocked

## 资源

- 安装 + 首次 develop 后 `/nix` 量级约数 GB（见会话时 `du -sh /nix/store` 记录）
- 未执行完整卸载（保留本机 Nix 以便后续开发）；如需回退按 `docs/nix-devshell.md` 卸载清单

## 未完成 / 跳过

- [跳过] Apple Silicon macOS 全流程
- [跳过] 本机完整 `pnpm qa` + `pnpm test:pwsh:full:assertions` + cargo 全量（可在 devshell 内按需补跑）
- [可选] 真实 `/etc/nix/nix.conf` China Apply/Restore 演练（adapter 已具备；需 sudo）

## 结论

Linux x86_64 上 **显式 `nix develop` 可复现工具链** 成立；macOS 待后续机器补测。Nix 仍保持可选，不接入 Core/Full 安装链。
