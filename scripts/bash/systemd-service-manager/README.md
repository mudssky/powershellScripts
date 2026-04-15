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
- `--start`：给 `install` 使用，安装完成后立即启动目标 unit。
- `--follow`：只给 `logs` 使用，持续跟随日志输出。

## Notes

- `start` / `stop` / `restart` / `status` / `logs` 这类命令依赖目标 unit 已经先执行过 `install`。
- `install` / `start` / `stop` / `restart` / `enable` / `disable` 这类 system scope 写操作在非 root 下会自动通过 `sudo` 重新执行脚本本身，因此不要求你手工把 `sudo` 写在命令前。

## Environment support

- `project.env` / `project.env.local` 中的变量会渲染到所有 service / timer task unit 的 `Environment=`。
- `services/<name>.env` / `services/<name>.env.local` 会覆盖项目级变量，并只作用于对应 service。
- `timers/<name>.env` / `timers/<name>.env.local` 会覆盖项目级变量，并只作用于对应 timer 生成的一次性 task service。
- 优先级保持为：
  - `<name>.env.local`
  - `<name>.env`
  - `project.env.local`
  - `project.env`

## fnm 推荐写法

对于 `system` scope 的 Node / fnm 工具，推荐在 env 文件里提供稳定的 `PATH` 和 `HOME`，不要使用 `/run/user/.../fnm_multishells/...` 这类会话级临时路径。

推荐把下面内容写到 `project.env.local` 或 `services/<name>.env.local`：

```dotenv
HOME=/home/administrator
PATH=/home/administrator/.local/share/fnm/node-versions/v24.11.0/installation/bin:/usr/local/bin:/usr/bin:/bin
```

然后 `COMMAND` 可以直接写成：

```dotenv
COMMAND=zread browse --host 0.0.0.0 --port 19681
```

如果你更在意稳定性，也可以直接把 `COMMAND` 写成绝对路径，但一般优先推荐“稳定 PATH + 裸命令”这条线，可读性更好。

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
systemd-service-manager install api --project /path/to/app --start
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
