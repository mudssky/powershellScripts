# WSL Ubuntu 22.04 原地升级到 24.04

## Goal

在现有 WSL 发行版 `Ubuntu-22.04`（Jammy）内原地升级到 Ubuntu 24.04 LTS（Noble），保留 home、已装包与用户配置；不使用 `wsl --export` / `--import` 迁移。

## Context（执行结果，2026-07-26）

- 宿主：Windows 11 build 26200；WSL 2.5.10.0
- 发行版注册名仍为 `Ubuntu-22.04`（Running，WSL2）
- **已完成原地升级**：`PRETTY_NAME=Ubuntu 24.04.4 LTS`，`VERSION_ID=24.04`，`VERSION_CODENAME=noble`
- 用户明确跳过 `wsl --export` 备份
- 宿主 `.wslconfig` 与客体 `/etc/wsl.conf` 已按仓库模板部署
- 附带修复：`wsl --list` NUL 清理从 `.Replace([char]0, '')` 改为 `-replace [char]0, ''`

## Requirements

1. **原地升级**：在同一 VHD/发行版实例内完成 22.04 → 24.04，不重建发行版。
2. **数据保留**：`/home/mudssky`、用户级 dotfiles、已装 apt 包尽可能保留。
3. **升级前快照**：用户明确跳过。
4. **WSL 约束**：`Prompt=lts` + `do-release-upgrade -f DistUpgradeViewNonInteractive`。
5. **Docker**：升级后检查 `docker`；若 Docker Desktop 集成失效，提示在 Desktop 设置中重新勾选该发行版。
6. **不自动 shutdown/unregister**。

## Acceptance Criteria

- [x] 用户确认跳过备份
- [x] 发行版内 `VERSION_ID=24.04`（Noble 24.04.4 LTS）
- [x] 默认用户仍为 `mudssky`
- [x] `systemctl is-system-running` = `running`
- [x] `/etc/wsl.conf` 与仓库模板一致
- [x] `docker`：CLI shim 提示需在 Docker Desktop 重新开启对该 distro 的 WSL integration（`docker-desktop` 发行版曾 Stopped）；用户仍在 `docker` 组
- [x] 未执行 `wsl --unregister`
- [x] NUL 解析 bug 已修，`Initialize-WslHost -WhatIf` 可识别 `Ubuntu-22.04` 且 exit 0

## Notes

- 发行版 **注册名** 仍是 `Ubuntu-22.04`，与内部 24.04 版本不一致；仓库脚本默认名 `Ubuntu-24.04` 若要匹配需另改参数或 rename（本任务未做）。
- 宿主 `.wslconfig` 若尚未 `wsl --shutdown`，mirrored 等项可能未完全生效。
- 升级命令曾以 hub 进程 `wsl-upgrade` 运行：`do-release-upgrade exit=0`。
