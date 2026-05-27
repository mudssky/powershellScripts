# rclone WebUI 自动挂载多个 OSS 设计

## Architecture

在 `rclone-ops.ps1` 中保留现有低层命令：

- `webui`：只启动 WebUI/RC。
- `mount`：继续作为手工 rclone mount 透传入口。
- `unmount`：继续卸载单个挂载点。

新增高层编排命令：

- `mount-all`：读取 JSON `mounts`，启动所有 enabled profile。
- `unmount-all`：读取 JSON `mounts`，卸载所有 enabled profile。
- `up`：确保 `rclone.conf` 可用，后台启动 WebUI，再执行 `mount-all`。
- `down`：执行 `unmount-all`，再停止 WebUI。

## JSON Contract

建议 schema：

```json
{
  "mounts": [
    {
      "name": "cloud-main",
      "enabled": true,
      "remote": "cloud-main:",
      "mountPoint": "mounts/cloud-main",
      "options": {
        "vfs-cache-mode": "writes",
        "cache-dir": ".runtime/cache/cloud-main",
        "vfs-cache-max-size": "20G",
        "vfs-cache-max-age": "24h",
        "dir-cache-time": "10m",
        "vfs-fast-fingerprint": true,
        "log-file": ".runtime/logs/mount-cloud-main.log"
      }
    }
  ]
}
```

字段约定：

- `name`：profile 名称，用于日志输出和 PID 文件名。
- `enabled`：可选，默认 `true`；`false` 时跳过。
- `remote`：必填，传给 rclone 的源路径，例如 `aliyun-test:` 或 `aliyun-test:bucket/path`。
- `mountPoint`：必填，本地挂载点。
- `options`：可选对象，键名转换为 `--<key>`；布尔 `true` 转为 flag，布尔 `false` 跳过，字符串/数字转为 `--<key>=<value>`。

## Path Resolution

- `--source` 默认仍为脚本目录下的 `rclone.config.local.json`。
- `mountPoint`、`cache-dir`、`log-file` 等本地路径如果是相对路径，按 JSON 主配置所在目录解析。
- 解析路径复用 `psutils/modules/config.psm1` 暴露的 `Resolve-ConfigPath`，继续支持 `~` 与环境变量占位符。
- `remote` 这类 rclone remote 路径不能当文件系统路径解析。

## Process And PID Files

- WebUI 继续写 `.runtime/webui.pid`。
- 配置化 mount 写 `.runtime/mounts/<safe-name>.pid`。
- 现有手工 `mount --background` 应改为基于 remote/mountPoint 生成 PID，避免多个手工 mount 覆盖同一个 `mount.pid`。
- `Stop-Process` 只用于 WebUI；mount 停止优先走平台卸载命令：
  - macOS：`diskutil unmount <mountPoint>`
  - Linux：`fusermount -u <mountPoint>`
  - 其他：`umount <mountPoint>`

## Operational Defaults

- OSS/S3 默认推荐 `vfs-cache-mode=writes`，兼顾写入兼容与磁盘占用。
- 如果用于大量随机读取、视频播放或对文件系统语义敏感的软件，可由用户在 profile 中改为 `full`。
- 每个 mount 使用独立 `cache-dir`，避免 rclone 多实例共享 VFS cache。
- `up` 默认后台启动 WebUI 且不自动打开浏览器，适合“部署”语义。

## Compatibility

- 不改变现有 `webui`、`mount`、`unmount` 调用方式。
- `rclone.conf` 仍由 `init-config` 从 `remotes` 生成。
- `up` 如果 `rclone.conf` 不存在，应自动生成；如果已存在则复用，避免意外覆盖。

## Risks

- 多 mount 启动过程中部分成功、部分失败时，需要清晰输出失败项；不做自动回滚，避免误卸载用户已有挂载。
- `down` 根据配置卸载，若用户修改了 `mountPoint`，旧挂载需要手工处理。
- 本地 `rclone.config.local.json` 已被忽略，修改它适合个人环境，但 example/README 仍要作为可复用模板。
