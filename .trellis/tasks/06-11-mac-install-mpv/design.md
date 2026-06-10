# macOS mpv 平台配置拆分设计

## Architecture and Boundaries

- `mpv.conf` 保持跨平台通用配置，只放 Windows/macOS/Linux 都能解析的选项。
- `mpv_local.conf` 继续作为 `.gitignore` 中的本机覆盖文件，承载平台专用配置和用户本地偏好。
- `install.ps1` 在首次安装或本地配置为空时生成平台默认覆盖；如果用户已经写过本地配置，脚本只提示不覆盖。
- macOS 上 `install.ps1` 额外生成 `~/Applications/mpv.app` AppleScript 外壳，让 Finder 能通过“打开方式”调用 Homebrew mpv。

## Data Flow and Contracts

- mpv 启动时读取 `mpv.conf`，再通过 `include="~~/mpv_local.conf"` 固定从 mpv 配置目录加载本地覆盖，避免命令行工作目录不同导致 include 失败。
- Windows 默认覆盖写入 `gpu-api=d3d11`、`d3d11-output-format=auto`、`ao=wasapi`。
- macOS 默认覆盖写入 `ao=coreaudio`，GPU API 保持自动选择，避免 Homebrew mpv 不支持 `gpu-api=metal` 时启动失败。
- Linux 默认覆盖保持注释说明，不强制指定音视频后端。
- `mpv.app` 的 `on open` 事件接收 Finder 传入文件列表，并用 `mpv -- <file...>` 启动命令行 mpv，避免文件名被识别为选项。

## Compatibility and Migration Notes

- 既有 `mpv_local.conf` 非空时不自动改写，避免覆盖用户本机设置。
- 既有空 `mpv_local.conf` 会被填入当前平台默认值。
- `mpv.conf` 删除 Windows 专用硬编码后，macOS 不再因 `d3d11` 和 `wasapi` 选项报错。
- 已存在的 `~/Applications/mpv.app` 会被安装脚本重建，以同步最新 mpv 路径和文档类型声明。

## Trade-offs

- 不新增可提交的 `mpv_windows.conf` / `mpv_macos.conf` 模板，减少 mpv 原生条件加载不确定性；平台默认值由安装脚本生成。
- macOS 不强行设置 `gpu-api=vulkan`，虽然本机可解析，但自动选择更稳，避免其他 Mac 环境缺少 Vulkan/MoltenVK 时失败。
- 选择 AppleScript 外壳而不是完整 Cocoa 应用，足够满足 Finder 文件关联，维护成本低。

## Operational and Rollback

- 回滚只需恢复 `mpv.conf` 中的 Windows 专用选项，并删除 `install.ps1` 的本地覆盖生成逻辑。
- 用户本机 `mpv_local.conf` 属于忽略文件；修改前按项目要求保留 `.bak` 备份。
