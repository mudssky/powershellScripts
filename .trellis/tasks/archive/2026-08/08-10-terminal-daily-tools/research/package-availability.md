# 包可用性与平台结论

核对日期：2026-08-10。

## 官方包源

- Homebrew `git-delta`：stable 0.19.2，提供 `delta`，包含 macOS 与 Linux bottle。
- Homebrew `tealdeer`：stable 1.8.1，提供 `tldr`，包含 macOS 与 Linux bottle。
- Scoop Main `delta`：stable 0.19.2，提供 `delta.exe`。
- Scoop Main `tealdeer`：stable 1.8.1，提供 `tldr.exe`；技术上支持原生 Windows。
- Homebrew `zsh-autosuggestions`：stable 0.7.1，推荐 source `${HOMEBREW_PREFIX}/share/zsh-autosuggestions/zsh-autosuggestions.zsh`。
- Homebrew `zsh-syntax-highlighting`：stable 0.8.0，推荐最后 source `${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`。
- Homebrew `dust`：stable 1.2.4，formula 名为 `dust`；现有 `du-dust` 命令已失效。

## TLDR 平台判断

TLDR 官方页面仓库同时包含 `common`、`windows`、`linux`、`osx` 等平台目录，因此原生 Windows 并非不可用；Scoop 也提供原生 `tldr.exe`。

本任务仍不在原生 Windows 安装 Tealdeer：用户的 Windows 主要作为 WSL 宿主，Linux/WSL 已能消费 `common + linux` 页面；Windows 再安装会增加一份独立 cache，收益不足。Delta 对原生 Windows Git 输出仍有直接价值，因此进入 Windows Core。

## 规划映射

| 工具 | Windows | macOS | Linux/WSL |
| --- | --- | --- | --- |
| Delta | Core / Scoop `delta` | Core / Homebrew `git-delta` | Full `terminal-extras` / Homebrew `git-delta` |
| Tealdeer | 不安装 | Core / Homebrew `tealdeer` | Full `terminal-extras` / Homebrew `tealdeer` |
| Zsh 两插件 | 不安装 | Core | 不安装 |
| Dust 修复 | 不变 | Core / Homebrew `dust` | 不变 |
