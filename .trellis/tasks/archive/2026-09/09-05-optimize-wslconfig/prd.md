# 优化 WSL 全局配置

## Goal

让仓库部署的 WSL 全局配置随宿主机资源自适应，只显式声明有意偏离 WSL 默认行为的选项，并在验证通过后安全部署到当前用户使其生效。

## Background

- 当前 `windows/wsl/.wslconfig` 固定分配 `16GB` 内存、4 个逻辑处理器和 `8GB` swap，不适合不同硬件规格。
- Microsoft WSL 文档当前说明：内存默认使用宿主机总内存的 50%，处理器默认使用全部逻辑处理器，swap 默认使用宿主机内存的 25%（向上取整到 GB）。
- `localhostForwarding`、`guiApplications`、`nestedVirtualization`、`dnsTunneling`、`firewall`、`autoProxy` 当前显式值均等于官方默认值；其中 `localhostForwarding` 在 mirrored 网络模式下还会被忽略。
- `networkingMode=mirrored`、`sparseVhd=true`、`hostAddressLoopback=true` 有意偏离当前官方默认值，分别提供 mirrored 网络、新 VHD 稀疏化和通过宿主机 IPv4 地址互访能力。
- `autoMemoryReclaim=gradual` 偏离当前默认的 `dropCache`；本任务选择恢复默认值，让缓存内存更及时地归还 Windows。
- 同一 WSL 设置还声明于 `config/install/windows-packages.psd1`，安装流水线按 Windows build 过滤后生成最终配置。

## Requirements

- 从模板和安装清单中删除固定的 `memory`、`processors`、`swap`，恢复 WSL 的宿主资源自适应默认行为。
- 从模板和安装清单中删除与官方默认值重复或在 mirrored 模式下无效的设置。
- 保留 `networkingMode=mirrored`、`sparseVhd=true` 和 `hostAddressLoopback=true`；后者用于通过 Windows 宿主机的 Tailscale/LAN IPv4 地址与 WSL 互访。
- 不再显式配置 `autoMemoryReclaim`，使用 WSL 当前默认的 `dropCache`。
- 新增 `windows/wsl/README.md`，说明相关 WSL 官方默认值、仓库显式覆盖值、各覆盖项的用途、生效条件、取舍、版本要求及配置生效方式；注明官方依据与核对日期，提醒默认值可能随 WSL 版本变化。
- 测试只验证 build 过滤、section/顺序生成和托管写入等机制，不断言仓库当前选用了某个具体配置值，也不要求生成结果与模板逐字相等。
- 保持现有 Windows 10/Windows 11 build 兼容过滤行为；不改变安装流水线的自动 shutdown 策略。
- 所有仓库修改和测试通过后，将新配置部署到当前用户的 `%UserProfile%\.wslconfig`；修改该本地配置前创建可读时间戳 `.bak`，随后执行 `wsl --shutdown` 使配置生效。

## Out of Scope

- 调整 WSL 客体内的 `/etc/wsl.conf`。
- 重构 Windows 安装流水线或改变 WSL 功能安装范围。
- 删除或重建现有发行版/VHD；`sparseVhd=true` 不承诺改造既有 VHD。

## Acceptance Criteria

- [x] 仓库模板与 Windows 安装清单都不再包含固定资源限制、重复默认项或 `autoMemoryReclaim=gradual`。
- [x] 仓库模板只显式包含 `networkingMode=mirrored`、`sparseVhd=true` 和 `hostAddressLoopback=true`。
- [x] `windows/wsl/README.md` 能直接回答省略项的默认行为，以及每个保留项为何存在、何时无效。
- [x] 生成配置仅包含满足目标 Windows build 的声明式非默认项，且旧 build 不出现现代 WSL 设置。
- [x] WSL 配置测试使用自包含测试数据验证生成机制，不绑定仓库当前配置偏好。
- [x] 现有配置写入的幂等、时间戳备份和 RestartRequired 行为保持通过。
- [ ] `pnpm qa`、`pnpm test:pwsh:all` 与 `git diff --check` 通过。
- [x] 当前用户 `.wslconfig` 已在备份后更新为新配置，并已执行 `wsl --shutdown`。

## Notes

- 官方依据：<https://learn.microsoft.com/windows/wsl/wsl-config> 和 <https://learn.microsoft.com/windows/wsl/networking>（访问于 2026-09-05）。
- `wsl --shutdown` 会终止全部运行中的 WSL 发行版，并可能中断 Docker Desktop 的 WSL 后端。
- 运行态确认新配置已加载：WSL 可见 16 个逻辑处理器和约 29.77 GiB 内存，替代旧的 4 核/16 GiB 固定限制；常驻 SSH 任务在 shutdown 后自动拉起 `Ubuntu-22.04`。
- 质量门禁已执行但受开发机环境影响未全绿：`pnpm qa` 因 Cargo 1.79 不支持 Rust 2024 edition 被阻断；`pnpm test:pwsh:all` 的 host 分支缺少 Pester 6.1.0，Linux 分支 921 通过、1 个与本次改动无关的 scoop shim 启动失败。Pester 5 全量覆盖为 940 通过、3 个 Pester 6.1.0 环境相关失败，覆盖率 62.69%；本次相关定向测试 28/28 通过。
- 本任务范围小、边界清晰，采用 PRD-only 轻量任务。
