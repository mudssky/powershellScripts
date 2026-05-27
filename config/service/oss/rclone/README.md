# rclone 通用运维入口

这个目录提供一套通用 rclone 运维入口，用于从 JSON 主配置生成本地 `rclone.conf`，并统一启动 WebUI/RC、挂载、复制、同步和校验等常用操作。真实密钥只保存在本地 JSON、进程环境变量和生成的 `rclone.conf` 中；示例文件只使用占位符。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `rclone.config.example.json` | JSON 配置模板，使用 `remotes` 数组表达多个 remote。 |
| `rclone.conf.example` | rclone 配置模板，只包含占位符。 |
| `rclone-ops.ps1` | 推荐使用的 PowerShell 运维脚本，支持配置生成、WebUI/RC、mount、copy、sync、check 等入口。 |
| `rclone-ops.mjs` | 保留的 Node.js 版本，便于对照和跨平台备用。 |
| `.gitignore` | 防止真实配置、运行时日志和挂载目录被提交。 |

## 配置格式

`rclone-ops` 只支持 JSON 主配置，不再用 `.env` 表达 remote 列表，也不兼容旧的 `RCLONE_REMOTE_NAMES` / `RCLONE_REMOTE_<NAME>_<KEY>` 平铺格式。PowerShell 版仍通过仓库的 `psutils/src/config` 读取标准 JSON，rclone 脚本层负责校验 `remotes` schema 与环境变量占位符替换。

核心约定：

1. 顶层必须包含非空 `remotes` 数组。
2. 每个 remote 必须包含 `name` 与 `type`。
3. remote 对象中除 `name` 外的字段会按原键名写入 `rclone.conf`。
4. 字符串值可使用 `${ENV_VAR}` 占位符，从当前进程环境变量读取密钥；缺失变量会直接报错。
5. 可选的 `webui` section 可配置 `addr`、`user`、`pass`，命令行参数与环境变量优先级高于 JSON。
6. 可选的 `mounts` 数组可配置多个自动挂载 profile；相对路径按 JSON 主配置所在目录解析。

示例：

```json
{
  "remotes": [
    {
      "name": "cloud-main",
      "type": "s3",
      "provider": "Other",
      "access_key_id": "${CLOUD_MAIN_ACCESS_KEY_ID}",
      "secret_access_key": "${CLOUD_MAIN_SECRET_ACCESS_KEY}",
      "endpoint": "https://s3.example.com",
      "region": "auto",
      "acl": "private"
    },
    {
      "name": "archive",
      "type": "s3",
      "provider": "Other",
      "access_key_id": "REPLACE_ME",
      "secret_access_key": "REPLACE_ME",
      "endpoint": "http://127.0.0.1:9000",
      "force_path_style": "true"
    }
  ],
  "webui": {
    "addr": "127.0.0.1:5572",
    "user": "admin",
    "pass": "${RCLONE_RC_PASS}",
    "log-file": ".runtime/logs/webui.log"
  },
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

## 前置条件

1. 安装 PowerShell 7+。
2. 安装 rclone，并确保 `rclone version` 可执行。
3. 准备 JSON 配置文件：

```bash
cp rclone.config.example.json rclone.config.local.json
# 编辑 rclone.config.local.json，填入真实 remote 配置；该文件已被 .gitignore 忽略。
```

如果使用 `${ENV_VAR}` 占位符，在运行 `init-config` 前导出对应变量：

```bash
export CLOUD_MAIN_ACCESS_KEY_ID='真实 ID'
export CLOUD_MAIN_SECRET_ACCESS_KEY='真实 Secret'
```

## 一键生成本地 rclone.conf

```bash
cd config/service/oss/rclone
pwsh ./rclone-ops.ps1 init-config --source rclone.config.local.json
```

如需覆盖已有本地配置：

```bash
pwsh ./rclone-ops.ps1 init-config --source rclone.config.local.json --overwrite
```

Node.js 版同等命令：

```bash
node rclone-ops.mjs init-config --source rclone.config.local.json --overwrite
```

## 健康检查

```bash
pwsh ./rclone-ops.ps1 doctor
```

该命令会检查：

- `rclone` 是否可执行。
- `rclone.conf` 是否存在。
- 已配置的 remote 名称。

## 启动 WebUI / RC

默认监听 `127.0.0.1:5572`。不带 `--background` 时是前台运行模式，命令会持续占用当前终端，并把 rclone 日志直接显示在当前终端；可打开 `http://127.0.0.1:5572` 确认状态，按 `Ctrl+C` 停止。后台模式才会把日志写入 `webui.log-file` 指定的文件，未配置时默认写入 `.runtime/logs/webui.log`。

WebUI 密码可以通过三种方式设置，优先级为命令行 `--pass` > 环境变量 `RCLONE_RC_PASS` > JSON `webui.pass`。如果 JSON 中写了 `${RCLONE_RC_PASS}`，运行前需要导出该环境变量；如果三者都未设置，rclone WebUI 会自动生成临时认证信息。

WebUI 后台日志同样可通过三种方式设置，优先级为命令行 `--log-file` > 环境变量 `RCLONE_LOG_FILE` > JSON `webui.log-file`。如果希望运行数据统一放到独立磁盘，可以把 `webui.log-file` 与各 mount 的 `mountPoint`、`cache-dir`、`log-file` 都改成绝对路径，例如 `/Volumes/Data/rclone/logs/webui.log`。

```bash
RCLONE_RC_PASS='强密码' pwsh ./rclone-ops.ps1 webui
```

后台启动且不自动打开浏览器：

```bash
RCLONE_RC_PASS='强密码' pwsh ./rclone-ops.ps1 webui --background --no-open-browser
```

停止后台 WebUI：

```bash
pwsh ./rclone-ops.ps1 stop-webui
```

> 安全提示：rclone WebUI 会启动 remote control API，默认绑定 localhost；如果 `--rc-addr` 绑定公网或局域网地址，应使用 `--rc-user` / `--rc-pass` 等认证方式。默认只绑定本机地址，除非你明确知道风险，不要改成 `0.0.0.0:5572`。

## 一键启动 WebUI 与自动挂载

`up` 会在缺少 `rclone.conf` 时先从 JSON 主配置生成本地配置，然后后台启动 WebUI，并挂载 `mounts` 中所有 `enabled: true` 的 profile。WebUI 默认不自动打开浏览器，适合日常部署。

```bash
RCLONE_RC_PASS='强密码' pwsh ./rclone-ops.ps1 up
```

停止整套服务：

```bash
pwsh ./rclone-ops.ps1 down
```

只批量挂载或卸载，不影响 WebUI：

```bash
pwsh ./rclone-ops.ps1 mount-all
pwsh ./rclone-ops.ps1 unmount-all
```

`mounts[].options` 会转换为 rclone mount 参数：字符串值生成 `--key=value`，布尔 `true` 生成 `--key`，布尔 `false` 会跳过。OSS/S3 日常写入建议从 `vfs-cache-mode=writes` 开始；如果你要直接播放大文件或频繁随机读取，可在对应 profile 中改为 `full`，同时给每个 profile 保持独立 `cache-dir`。

### mounts 配置说明

每个 `mounts[]` 条目代表一个自动挂载 profile：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `name` | 是 | profile 名称，用于日志输出和 PID 文件名；建议与 remote 同名。 |
| `enabled` | 否 | 是否启用该挂载；省略时默认启用，设为 `false` 会被 `up` / `mount-all` 跳过。 |
| `remote` | 是 | rclone 远端路径，例如 `aliyun-test:` 或 `aliyun-test:bucket/path`。 |
| `mountPoint` | 是 | 本地挂载目录；相对路径按 JSON 主配置所在目录解析。 |
| `options` | 否 | 透传给 `rclone mount` 的参数对象；字符串生成 `--key=value`，布尔 `true` 生成 `--key`。 |

常用 `options`：

| 参数 | 示例值 | 说明 |
| --- | --- | --- |
| `vfs-cache-mode` | `writes` | VFS 文件缓存模式，决定 rclone 是否把读写文件缓存在本地磁盘。OSS/S3 场景建议从 `writes` 起步。 |
| `cache-dir` | `.runtime/cache/aliyun-test` | VFS 缓存目录。每个挂载必须使用独立目录，避免多个 mount 共享缓存导致数据风险。 |
| `vfs-cache-max-size` | `20G` | 缓存目录的目标上限。rclone 会按轮询周期清理旧缓存；打开中的文件不会被强制驱逐，所以实际占用可能短暂超过该值。 |
| `vfs-cache-max-age` | `24h` | 缓存文件距上次访问多久后可被清理。越大越利于重复读取，越小越省磁盘。 |
| `dir-cache-time` | `10m` | 目录列表缓存时间。越大越少请求远端、浏览更快；远端被其他工具修改后，变化可能更晚显示。 |
| `vfs-fast-fingerprint` | `true` | 使用较快但略不精确的指纹判断缓存文件变化。对 S3/OSS 这类对象存储通常能减少额外请求。 |
| `log-file` | `.runtime/logs/mount-aliyun-test.log` | 后台挂载日志文件。排查挂载失败、权限、缓存写回问题时先看这里。 |

`vfs-cache-mode` 可选值：

| 值 | 行为 | 适合场景 |
| --- | --- | --- |
| `off` | 默认值，基本不使用本地文件缓存；写入兼容性最差。 | 只读浏览、简单顺序读取。 |
| `minimal` | 只在文件同时读写时缓存到磁盘。 | 偶尔写入，想尽量省磁盘。 |
| `writes` | 只读文件直接从远端读；写入和读写文件先落本地缓存，再上传远端。 | 日常 OSS/S3 挂载推荐值，兼顾兼容性和磁盘占用。 |
| `full` | 读写都经过本地缓存，文件系统兼容性最好，但最占磁盘。 | 大文件播放、频繁随机读取、对 seek/编辑行为敏感的软件。 |

如果不确定怎么选，先用 `writes`；遇到视频拖动卡顿、应用频繁随机读、或者软件要求更完整的本地文件语义，再把对应 profile 改成 `full` 并适当调大 `vfs-cache-max-size`。

## 常用运维命令

列出 remote 根路径：

```bash
pwsh ./rclone-ops.ps1 lsd cloud-main:
pwsh ./rclone-ops.ps1 ls archive:bucket-name/path
```

挂载 remote：

```bash
mkdir -p mounts/cloud-main
pwsh ./rclone-ops.ps1 mount cloud-main: mounts/cloud-main -- --vfs-cache-mode writes
```

后台挂载：

```bash
pwsh ./rclone-ops.ps1 mount cloud-main: mounts/cloud-main --background -- --vfs-cache-mode writes
```

卸载挂载点：

```bash
pwsh ./rclone-ops.ps1 unmount mounts/cloud-main
```

复制对象（不会删除目标端多余文件）：

```bash
pwsh ./rclone-ops.ps1 copy ./local-dir cloud-main:bucket-name/path -- --progress
```

同步对象默认 dry-run，避免误删：

```bash
pwsh ./rclone-ops.ps1 sync ./local-dir cloud-main:bucket-name/path -- --progress
```

确认 dry-run 输出后，显式追加 `--run` 才会真实执行：

```bash
pwsh ./rclone-ops.ps1 sync ./local-dir cloud-main:bucket-name/path --run -- --progress
```

校验两端数据：

```bash
pwsh ./rclone-ops.ps1 check ./local-dir cloud-main:bucket-name/path -- --one-way
```

## Node.js 版本

本目录保留 `rclone-ops.mjs`。如果你更希望使用 Node.js 版本，可将上面的 `pwsh ./rclone-ops.ps1` 替换为 `node rclone-ops.mjs`，命令语义保持一致。

## 安全边界

- 不自动删除远端数据。
- `sync` 默认 `--dry-run`，真实同步必须显式传 `--run`。
- 不在 README、example 或 Git 中保存真实密钥。
- 不自动安装 rclone；缺失时由 `doctor` 提示。

## 参考

- rclone `rcd` 官方文档：<https://rclone.org/commands/rclone_rcd/>
- rclone GUI 官方文档：<https://rclone.org/gui/>
- rclone RC 官方文档：<https://rclone.org/rc/>
