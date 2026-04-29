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

默认监听 `127.0.0.1:5572`。不带 `--background` 时是前台运行模式，命令会持续占用当前终端；如果没有持续输出，通常表示 `rclone rcd` 仍在运行，可打开 `http://127.0.0.1:5572` 或查看 `.runtime/logs/webui.log` 确认状态，按 `Ctrl+C` 停止。

如果未设置 `RCLONE_RC_PASS`，rclone WebUI 会自动生成临时认证信息；建议日常运维显式设置强密码：

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
