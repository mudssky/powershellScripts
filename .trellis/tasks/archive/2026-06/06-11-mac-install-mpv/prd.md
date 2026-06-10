# mac 安装 mpv

## Goal

在 macOS 上安装 mpv，并通过平台配置拆分让本仓库的 `config/software/mpv` 配置被 mpv 正确加载。

## User Value

- 用户可以在 macOS 上直接使用仓库内维护的 mpv 配置、快捷键、脚本和可选插件。
- 安装方式应尽量复用现有脚本，减少手工复制配置造成的漂移。

## Confirmed Facts

- 当前机器是 macOS/Darwin ARM64。
- 本机已安装 `pwsh`：`/opt/homebrew/bin/pwsh`。
- 本机已安装 Homebrew：`/opt/homebrew/bin/brew`。
- 当前 `mpv` 命令未在 PATH 中发现。
- 后续确认 Homebrew 已安装 `mpv 0.41.0_6`，命令位于 `/opt/homebrew/bin/mpv`。
- `config/software/mpv/install.ps1` 已包含 macOS/Linux 分支：通过 `brew install mpv` 安装 mpv，并将仓库配置软链到 `~/.config/mpv`。
- `README.md` 已说明脚本会自动检测 Windows/macOS/Linux 并链接配置。
- ctx7 查询到的 mpv 文档源确认 Homebrew 是 macOS 上的 mpv 安装路径之一；Apple Silicon Homebrew 默认路径为 `/opt/homebrew/bin`。
- `mpv.conf` 现有 Windows 专用选项 `gpu-api=d3d11`、`d3d11-output-format=auto`、`ao=wasapi` 会在 macOS 上造成配置解析错误。
- `include="mpv_local.conf"` 在命令行工作目录不是配置目录时会导致 `mpv_local.conf` 查找失败。

## Requirements

- macOS 安装应使用 Homebrew 安装 mpv。
- 配置目标应为 `~/.config/mpv`，并链接到仓库目录 `config/software/mpv`。
- 不应在 macOS 上执行 Windows 专用的注册脚本 `registerMpv.ps1`。
- 若只执行安装，不需要修改代码。
- 平台专用配置应从通用 `mpv.conf` 拆出，避免 macOS 加载 Windows 选项。
- 安装脚本应在本地配置不存在或为空时生成当前平台默认覆盖。
- 若本地配置非空，安装脚本不得覆盖用户已有设置。
- macOS 应创建 Finder 可识别的 `~/Applications/mpv.app` 外壳，方便通过“打开方式”点击视频文件。
- 改造脚本需保持 Windows/Linux 现有行为兼容。

## Acceptance Criteria

- [ ] `brew install mpv` 能安装或确认已安装 mpv。
- [ ] `~/.config/mpv` 指向仓库的 `config/software/mpv` 配置目录。
- [ ] `pwsh ./config/software/mpv/install.ps1 -Check` 在安装完成后返回成功。
- [ ] macOS 上不会触发 Windows 注册逻辑。
- [ ] macOS 执行 `mpv --version` 不再输出 `d3d11`、`wasapi` 或 `mpv_local.conf` include 错误。
- [ ] Windows 专用 `gpu-api=d3d11`、`d3d11-output-format=auto`、`ao=wasapi` 只存在于本地平台覆盖生成逻辑中。
- [ ] macOS 安装后存在 `~/Applications/mpv.app`，Finder 可通过“打开方式”选择它打开视频。

## Notes

- 当前任务已扩大为配置和安装脚本改造，补充 `design.md` 和 `implement.md`。

## Open Questions

- 无阻塞问题；用户已要求做平台拆分。
