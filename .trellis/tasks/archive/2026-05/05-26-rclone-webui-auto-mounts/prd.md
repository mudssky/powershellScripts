# rclone WebUI 自动挂载多个 OSS

## Goal

为 `config/service/oss/rclone/rclone-ops.ps1` 新增配置化启动能力：基于 JSON 主配置后台启动 rclone WebUI，并自动挂载多个 OSS / S3 remote，减少手工输入长命令与漏配 VFS 参数的风险。

## Confirmed Facts

- 当前主要入口是 `config/service/oss/rclone/rclone-ops.ps1`。
- 当前 JSON 主配置只包含 `remotes` 与 `webui`，没有 `mounts` 配置段。
- 当前 `mount` 命令是通用转发：`rclone mount <remote:path> <mount-point> --config=<rclone.conf> <passthrough>`。
- 当前后台 `mount` PID 固定写入 `.runtime/mount.pid`，不适合多个 mount 并存。
- 本地配置已有多个 S3/OSS remote，需要支持多挂载 profile。
- rclone mount 文档建议对象存储写入兼容场景至少使用 `--vfs-cache-mode writes`；多实例使用 VFS cache 时应为不同挂载提供独立 cache 目录，避免重叠缓存带来的数据风险。

## Requirements

- 新增顶层 `mounts` JSON 配置段，用于描述多个可启用/禁用的挂载 profile。
- 新增组合命令 `up`：确保 `rclone.conf` 可用，后台启动 WebUI，然后按配置启动所有 enabled mount。
- 新增组合命令 `down`：卸载配置中的 mounts，并停止后台 WebUI。
- 新增独立批量命令 `mount-all` / `unmount-all`，便于只管理挂载，不影响 WebUI。
- 保留现有 `webui`、`mount`、`unmount` 命令语义，避免破坏手工运维习惯。
- 每个 mount profile 必须有独立 PID 文件、日志文件和 cache 目录，避免多挂载互相覆盖。
- 相对路径默认按 JSON 主配置所在目录解析，保证从仓库根目录或 rclone 目录执行时行为一致。
- `mounts.options` 支持布尔 flag 与字符串值，并允许 `${ENV_VAR}` 占位符。
- 示例配置与 README 需要说明推荐的 OSS/S3 mount 参数。

## Acceptance Criteria

- [ ] `rclone.config.example.json` 包含 `mounts` 示例，展示多个 profile、独立 cache/log、`vfs-cache-mode` 推荐值。
- [ ] `rclone-ops.ps1 help` 展示 `up`、`down`、`mount-all`、`unmount-all` 的用法。
- [ ] `pwsh ./rclone-ops.ps1 up --background` 或等价命令能后台启动 WebUI 并启动所有 enabled mounts。
- [ ] 多个 mounts 启动时生成不同 PID 文件，例如 `.runtime/mounts/<name>.pid`。
- [ ] `down` / `unmount-all` 按配置卸载所有 enabled mounts，不依赖单一 `.runtime/mount.pid`。
- [ ] 缺少 `mounts` 或没有 enabled profile 时给出清晰提示，不影响单独 `webui` 使用。
- [ ] 配置缺少 `name`、`remote` 或 `mountPoint` 时抛出包含配置路径的清晰错误。
- [ ] Pester 测试覆盖 mounts 配置解析、参数生成、布尔 flag、禁用 profile、独立 PID 路径。
- [ ] README 包含一键启动和一键停止示例。

## Out Of Scope

- 不自动安装 rclone、FUSE、macFUSE、WinFsp 等系统依赖。
- 不新增系统级开机自启、launchd、systemd 或 Windows 服务。
- 不修改 Node.js 备用版 `rclone-ops.mjs`，除非后续单独要求同步能力。
- 不把真实密钥写入 example、README 或 Git。

## Open Questions

- 已决策：将本地 `rclone.config.local.json` 的 4 个 remote 都写入 `mounts` 并启用，便于用户直接执行 `up` 测试；只新增 mount/cache/log 路径，不改动真实密钥字段。
