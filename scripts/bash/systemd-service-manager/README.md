# Systemd Service Manager

一个基于 Bash 的轻量 systemd `service` / `timer` 管理器。

## Commands

- `init`：在项目目录下生成 `deploy/systemd/` 骨架、`README.md`、`*.example` 和默认可编辑配置。
- `list`：列出项目中声明的 services 与 timers，方便确认命名和管理范围。
- `install`：把 `.conf` / `.env` 渲染成 `.service` / `.timer`，并安装到 systemd 目录；支持 `--dry-run` 预览。
- `uninstall`：删除当前工具生成的 unit 文件。
- `start`：启动指定 service 或 timer。
- `stop`：停止指定 service 或 timer。
- `restart`：重启指定 service 或 timer。
- `status`：查看指定对象的 `unit`、`scope`、`installed`、`enabled`、`active` 状态。
- `logs`：查看 journald 日志；可配合 `--follow` 持续跟踪。
- `enable`：启用开机或用户会话自启动。
- `disable`：禁用开机或用户会话自启动。

## Common options

- `--project <path>`：指定项目根目录，默认使用当前目录。
- `--dry-run`：只输出计划生成或安装的结果，不真正写入 systemd unit。
- `--follow`：只给 `logs` 使用，持续跟随日志输出。

## Build

```bash
bash scripts/bash/systemd-service-manager/build.sh
```

## Outputs

- `bin/systemd-service-manager`
- `scripts/bash/systemd-service-manager/systemd-service-manager.local.sh`

打包后的单文件产物内嵌了 `init` 所需模板，因此把脚本单独复制到其他目录后，仍可直接执行 `init` 生成 `deploy/systemd/` 骨架。

## Examples

```bash
systemd-service-manager init
systemd-service-manager list --project /path/to/app
systemd-service-manager install service api --project /path/to/app
systemd-service-manager install timer cleanup --project /path/to/app --dry-run
systemd-service-manager logs service api --project /path/to/app --follow
```

## Test

```bash
pnpm run test:systemd-service-manager
```

## Quality Gate

```bash
pnpm run qa:systemd-service-manager
pnpm qa
```
