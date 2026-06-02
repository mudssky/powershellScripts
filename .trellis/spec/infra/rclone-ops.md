# rclone Ops Guidelines

> 本规范记录 `config/service/oss/rclone/rclone-ops.ps1` 的 JSON 主配置、WebUI 与自动挂载契约。

## Scenario: rclone WebUI 与自动挂载

### 1. Scope / Trigger

- Trigger: 修改 `config/service/oss/rclone/rclone-ops.ps1`、`rclone.config.example.json`、`README.md` 或 `tests/RcloneOps.Tests.ps1` 中与 WebUI、RC、mount、VFS cache、日志路径有关的逻辑。
- Scope: `rclone-ops.ps1` 是推荐运维入口，负责从 JSON 主配置生成 `rclone.conf`、启动 WebUI/RC、启动/停止配置化 mounts。
- Design intent: 用一个 JSON 主配置管理 remotes、WebUI 和多个 mount profile，避免手工输入长命令导致漏配 VFS cache、日志或 PID 文件。

### 2. Signatures

- `pwsh ./rclone-ops.ps1 init-config --source <json> [--config <rclone.conf>] [--overwrite]`
- `pwsh ./rclone-ops.ps1 webui [--background] [--addr <host:port>] [--user <name>] [--pass <secret>] [--log-file <path>] [--no-open-browser]`
- `pwsh ./rclone-ops.ps1 stop-webui`
- `pwsh ./rclone-ops.ps1 mount <remote:path> <mount-point> [--background] -- <rclone mount flags>`
- `pwsh ./rclone-ops.ps1 unmount <mount-point>`
- `pwsh ./rclone-ops.ps1 mount-all [--source <json>] [--config <rclone.conf>]`
- `pwsh ./rclone-ops.ps1 unmount-all [--source <json>]`
- `pwsh ./rclone-ops.ps1 up [--source <json>] [--config <rclone.conf>]`
- `pwsh ./rclone-ops.ps1 down [--source <json>]`

### 3. Contracts

- 顶层 `remotes` 必须是非空数组；每个 remote 至少包含 `name` 与 `type`。
- `webui.addr`、`webui.user`、`webui.pass`、`webui.log-file` 可从 JSON 读取。
- `up` 必须先从 JSON 主配置刷新生成 `rclone.conf`，确保 WebUI 与 mount 看到的 remote 名称和密钥与 JSON 一致。
- WebUI 选项优先级：
  - `addr`: 命令行 `--addr` > `RCLONE_RC_ADDR` > `webui.addr` > 默认 `127.0.0.1:5572`
  - `pass`: 命令行 `--pass` > `RCLONE_RC_PASS` > `webui.pass` > 空
  - `log-file`: 命令行 `--log-file` > `RCLONE_LOG_FILE` > `webui.log-file` > `.runtime/logs/webui.log`
- 顶层 `mounts` 是可选数组；`up` / `mount-all` 只处理 `enabled` 非 `false` 的 profile。
- 每个 mount profile 必须包含：
  - `name`: profile 名称，用于日志输出和 PID 文件名。
  - `remote`: rclone remote 路径，例如 `aliyun-test:`、`aliyun-test:bucket` 或 `aliyun-test:bucket/prefix`。
  - `mountPoint`: 本地挂载点。
- `mounts[].options` 透传为 rclone mount flag：
  - 字符串/数字值生成 `--key=value`
  - 布尔 `true` 生成 `--key`
  - 布尔 `false` 或空值跳过
- `mountPoint`、`cache-dir`、`log-file`、`webui.log-file` 支持 `~`、环境变量占位符和绝对路径；相对路径按 JSON 主配置所在目录解析。
- 配置化 mount 默认补齐独立 `cache-dir` 和 `log-file`；多 mount 不得共享同一个 VFS cache 目录。
- 配置化 mount PID 文件写入 `.runtime/mounts/<safe-name>.pid`；手工后台 mount 使用独立 `manual-<safe-name>.pid`，不得回退到单一 `.runtime/mount.pid`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
| --- | --- |
| 主配置不是 `.json` | 抛出 `rclone-ops 仅支持 JSON 主配置` |
| 缺少 `remotes` 或数组为空 | `init-config` 抛出包含 `remotes` 的清晰错误 |
| remote 缺少 `name` 或 `type` | 抛出包含 `remotes[index]` 上下文的错误 |
| `${VAR}` 占位符缺少环境变量 | 抛出 `环境变量未设置: VAR（context）` |
| mount 缺少 `name`、`remote` 或 `mountPoint` | 抛出包含 `mounts[index]` 的错误 |
| `mounts` 缺失或全部禁用 | `mount-all` / `unmount-all` 输出跳过提示并返回 0 |
| `cache-dir` 或 `log-file` 是相对路径 | 按 JSON 主配置所在目录解析成绝对路径 |
| 后台 WebUI 配置了 `webui.log-file` | 创建日志父目录，并把 `--log-file=<path>` 传给 rclone |
| 后台进程启动后立即退出 | 清理 PID 文件、输出可用的日志尾部并返回非 0，避免误报启动成功 |
| `down` / `unmount-all` 遇到普通目录或不存在路径 | 输出跳过提示、清理对应 PID 文件并返回成功 |
| `stop-webui` 遇到过期 PID 文件 | 清理 PID 文件并返回成功 |

### 5. Good/Base/Bad Cases

- Good: 本地配置把运行数据统一放到独立磁盘，例如 `webui.log-file=/Volumes/Data/rclone/logs/webui.log`、`mountPoint=/Volumes/Data/rclone/mounts/<name>`、`cache-dir=/Volumes/Data/rclone/cache/<name>`、`log-file=/Volumes/Data/rclone/logs/mount-<name>.log`。
- Good: OSS/S3 mount 默认使用 `vfs-cache-mode=writes`，并为每个 profile 配独立 cache 目录。
- Base: 示例配置使用仓库相对路径 `.runtime/cache/<name>` 和 `.runtime/logs/<file>`，便于开箱试用。
- Bad: macOS 上使用 Homebrew 版 rclone 执行 `rclone mount`；该版本可能不支持 mount，应使用官方预编译二进制并安装 macFUSE 或 FUSE-T。
- Bad: 多个 mount 共用同一个 `cache-dir`，可能造成 VFS cache 互相污染。
- Bad: 把真实 `rclone.config.local.json` 或密钥提交到 Git。

### 6. Tests Required

- Pester 覆盖 JSON remotes 生成、环境变量占位符替换、旧平铺格式拒绝。
- Pester 覆盖 `webui.pass` 与 `webui.log-file` 的 JSON 读取和路径解析。
- Pester 覆盖 mounts 解析、禁用 profile 跳过、必填字段错误、布尔 flag、路径解析和独立 PID 文件。
- Pester 覆盖普通目录执行 `unmount` 时幂等跳过，避免未挂载目录被当成失败。
- Pester 覆盖 `stop-webui` 遇到过期 PID 文件时清理文件并返回成功。
- 后台启动失败应在命令返回值和日志尾部中体现，不能只留下过期 PID 文件让用户翻日志排查。
- 修改 PowerShell 脚本逻辑后运行 `pnpm test:pwsh:qa` 与根目录 `pnpm qa`。
- 只修改 README/example 时至少运行定向 markdown 检查与 `git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```json
{
  "mounts": [
    {
      "name": "a",
      "remote": "a:",
      "mountPoint": "mounts/a",
      "options": { "cache-dir": ".runtime/cache/shared" }
    },
    {
      "name": "b",
      "remote": "b:",
      "mountPoint": "mounts/b",
      "options": { "cache-dir": ".runtime/cache/shared" }
    }
  ]
}
```

问题：多个 mount 共用 VFS cache 目录，排查写回和缓存一致性问题会很困难。

#### Correct

```json
{
  "webui": {
    "addr": "127.0.0.1:5572",
    "user": "admin",
    "pass": "${RCLONE_RC_PASS}",
    "log-file": "/Volumes/Data/rclone/logs/webui.log"
  },
  "mounts": [
    {
      "name": "a",
      "remote": "a:bucket",
      "mountPoint": "/Volumes/Data/rclone/mounts/a",
      "options": {
        "vfs-cache-mode": "writes",
        "cache-dir": "/Volumes/Data/rclone/cache/a",
        "log-file": "/Volumes/Data/rclone/logs/mount-a.log"
      }
    }
  ]
}
```

理由：WebUI 日志、挂载点、VFS cache 和 mount 日志都收口到一个运行目录，同时保持每个 mount 的 cache 隔离。
