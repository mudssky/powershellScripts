# deploy/systemd

这个目录存放项目的 systemd `service` / `timer` 配置。

## 推荐默认值

- `DEFAULT_SCOPE=system`
- `project.env.local > project.env`
- `<name>.env.local > <name>.env`

## 常见文件

- `project.conf` / `project.conf.example`
- `project.env` / `project.env.example`
- `services/*.conf`
- `timers/*.conf`
