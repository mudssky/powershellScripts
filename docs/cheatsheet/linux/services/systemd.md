
# 📘 Systemd Cheatsheet

> Systemd 是 Linux 系统中 PID=1 的系统和服务管理器，以下是最常用的命令和配置速查。

---

## 一、systemctl — 服务管理核心命令

### 🔧 服务生命周期管理

| 操作 | 命令 |
|------|------|
| **启动**服务 | `systemctl start <unit>` |
| **停止**服务 | `systemctl stop <unit>` |
| **重启**服务 | `systemctl restart <unit>` |
| **重载**配置（不中断服务） | `systemctl reload <unit>` |
| **查看状态** | `systemctl status <unit>` |
| **开机自启** | `systemctl enable <unit>` |
| **关闭自启** | `systemctl disable <unit>` |
| **启用并立即启动** | `systemctl enable --now <unit>` |
| **禁用并立即停止** | `systemctl disable --now <unit>` |
| **屏蔽服务**（禁止启动） | `systemctl mask <unit>` |
| **取消屏蔽** | `systemctl unmask <unit>` |

### 📋 查询与列出

| 操作 | 命令 |
|------|------|
| 列出所有 **正在运行** 的服务 | `systemctl` 或 `systemctl list-units --type=service` |
| 列出 **所有** 服务（含 inactive） | `systemctl list-units --all --type=service` |
| 列出 **已启用** 的服务 | `systemctl list-unit-files --type=service` |
| 列出 **失败** 的服务 | `systemctl --failed` |
| 查看服务是否 **启用** | `systemctl is-enabled <unit>` |
| 查看服务是否 **运行** | `systemctl is-active <unit>` |
| 列出服务 **依赖关系** | `systemctl list-dependencies <unit>` |
| 查看 unit 的 **底层文件路径** | `systemctl show -p FragmentPath <unit>` |

### 🔄 系统级操作

| 操作 | 命令 |
|------|------|
| 重载所有 unit 文件（修改后必须执行） | `systemctl daemon-reload` |
| 重启系统 | `systemctl reboot` |
| 关机 | `systemctl poweroff` |
| 挂起 | `systemctl suspend` |
| 休眠 | `systemctl hibernate` |
| 切换到救援模式 | `systemctl rescue` |
| 切换到紧急模式 | `systemctl emergency` |
| 查看默认启动目标 | `systemctl get-default` |
| 设置默认启动目标 | `systemctl set-default multi-user.target` |

---

## 二、Unit 文件详解

### 📁 Unit 文件存放路径

| 路径 | 说明 |
|------|------|
| `/etc/systemd/system/` | **管理员自定义**（最高优先级） |
| `/run/systemd/system/` | 运行时动态生成 |
| `/usr/lib/systemd/system/` | 发行版/软件包自带 |
| `/lib/systemd/system/` | 同上（部分发行版） |
| `~/.config/systemd/user/` | 当前用户自定义的 **user unit**（仅当前用户可见） |
| `/etc/systemd/user/` | 系统范围提供的 **user unit**，供各用户实例加载 |
| `/usr/lib/systemd/user/` | 发行版/软件包自带的 **user unit** |

> ⚠️ 优先级：`/etc/` > `/run/` > `/usr/lib/`

### 👥 系统服务 vs 用户服务

systemd 实际上有两类常见运行域：

- **系统服务（system service）**：由 PID 1 管理，常用 `systemctl <command>` 操作。
- **用户服务（user service）**：由某个用户自己的 systemd 实例管理，常用 `systemctl --user <command>` 操作。

| 维度 | 系统服务 | 用户服务 |
|------|----------|----------|
| 管理者 | 系统级 systemd（PID 1） | 当前用户的 systemd 实例 |
| 常见 unit 路径 | `/etc/systemd/system/` | `~/.config/systemd/user/` |
| 常见命令 | `systemctl start nginx` | `systemctl --user start my-agent` |
| 日志查看 | `journalctl -u nginx` | `journalctl --user -u my-agent` |
| 权限边界 | 通常需要 `sudo`；可在 unit 内再切换 `User=` | 默认只能代表当前用户运行 |
| 生命周期 | 跟随系统启动/停止，不依赖用户登录 | 默认跟随用户会话；退出登录后通常会结束 |
| 开机自启 | 适合系统启动后立即拉起 | 适合登录后或启用 lingering 后拉起 |
| 典型资源范围 | 系统目录、低端口、设备、挂载、系统网络 | 用户家目录、桌面会话、个人开发工具 |

### 🧭 典型使用场景

**更适合系统服务的场景：**

- Web API、数据库、反向代理、队列消费者等长期后台服务
- 需要在**没人登录**时也持续运行的进程
- 需要访问 `/var/lib`、`/var/log`、`/etc`、块设备、挂载点、系统网络配置的任务
- 需要监听低端口（如 `80` / `443`）或和其他系统服务建立启动依赖的程序
- 机器级定时任务，例如备份、日志轮转、磁盘巡检、系统同步

**更适合用户服务的场景：**

- 某个开发者自己的同步、代理、通知、常驻 CLI helper、个人守护进程
- 配置和数据都放在用户家目录下，不希望引入 `sudo`
- 每个用户都可能有自己的一份实例，互不干扰
- 个人定时任务，例如同步 dotfiles、定时拉代码、清理下载目录

### ⚠️ 用户服务最容易忽略的一点

如果用户服务需要在**退出登录后继续运行**，通常还要启用 lingering：

```bash
sudo loginctl enable-linger <user>
```

否则很多发行版上，用户会话结束后，该用户的 systemd 实例也会被回收。

### ✅ 选型建议

- 你在做“机器上的正式服务”时，优先选 **系统服务**
- 你在做“某个用户自己的后台工具”时，优先选 **用户服务**
- 如果一个工具既想服务服务器部署，也想服务开发者本地常驻工具，最好同时支持两种模式

### 📝 Service Unit 文件模板

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application Service
Documentation=https://example.com/docs
After=network.target mysql.service    # 在哪些服务之后启动
Wants=mysql.service                   # 弱依赖（推荐）
Requires=network.target               # 强依赖（任一失败则本服务也失败）
Before=nginx.service                  # 在哪些服务之前启动
Conflicts=oldapp.service              # 冲突的服务

[Service]
Type=simple              # 启动类型（见下表）
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp
Environment="NODE_ENV=production"
Environment="PORT=3000"
ExecStart=/usr/bin/node /opt/myapp/app.js
ExecStartPre=/opt/myapp/pre-start.sh       # 启动前执行
ExecStartPost=/opt/myapp/post-start.sh     # 启动后执行
ExecReload=/bin/kill -HUP $MAINPID         # 重载命令
ExecStop=/opt/myapp/graceful-stop.sh       # 停止命令
Restart=on-failure        # 重启策略
RestartSec=5s             # 重启间隔
TimeoutStartSec=60s
TimeoutStopSec=30s

# 安全沙箱选项
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/myapp /var/lib/myapp

[Install]
WantedBy=multi-user.target    # enable 时链接到该 target
Alias=myapp.service           # 别名
```

### ⚠️ ExecStart / Command 配置要点

`systemd` 里的 `ExecStart=` 和你在交互 shell 里敲命令，不是同一个运行环境。

最常见的坑有这些：

- `systemd` 默认**不会读取**你的 `.bashrc`、`.zshrc`、`profile`，所以不要假设交互 shell 里的 `PATH` 一定存在。
- `ExecStart=` 的**第一个可执行程序**最好是绝对路径，例如 `/usr/bin/node`、`/usr/bin/env`、`/usr/bin/bash`。
- 如果你想继续写裸命令，例如 `zread`、`pm2`、`pnpm`，建议写成 `/usr/bin/env <command> ...`，并显式提供 `PATH`。
- 需要切目录时优先用 `WorkingDirectory=`，不要把 `cd /path && ...` 全塞进 `ExecStart=`。
- 需要环境变量时，优先用 `Environment=` 或 `EnvironmentFile=`，而不是把一大串 `export` 硬塞进命令。
- 如果确实需要 shell 特性（如 `&&`、变量展开、`eval`），再用 `/usr/bin/env bash -lc '...'` 包一层。
- 不是所有命令都适合做 `Type=simple` 常驻服务。像“打开浏览器”“交互选择版本”“依赖 TTY”的命令，在终端里能跑，不代表在 systemd 里会持续驻留。

一个非常实用的判断标准：

- 命令在终端里启动后会**长期前台占用**，适合 `Type=simple`
- 命令启动后会**立即退出**、拉起子进程、弹浏览器、弹菜单，通常不适合作为常驻服务入口

### 📦 npm / fnm 安装的命令如何部署为 systemd 服务

很多 Node CLI 工具是通过 `npm -g` / `pnpm add -g` / `fnm` 安装的。  
这类命令在终端里能直接运行，往往只是因为当前 shell 已经提前配置好了 `PATH`。

systemd 下更推荐下面两种写法。

#### 方案 A：固定稳定 PATH（推荐）

适合长期运行的 `system service`。

关键思路：

- `ExecStart=` 用 `/usr/bin/env <command>`
- `Environment=` 明确给出稳定的 `PATH`
- 不要使用 `/run/user/.../fnm_multishells/...` 这类会话级临时路径

示例：

```ini
[Service]
Type=simple
User=administrator
Group=administrator
WorkingDirectory=/home/administrator/projects/myapp
Environment="HOME=/home/administrator"
Environment="PATH=/home/administrator/.local/share/fnm/node-versions/v24.11.0/installation/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/env zread browse --host 0.0.0.0 --port 19681
Restart=always
RestartSec=3s
```

这条线的优点是最稳定、最容易排障。

#### 方案 B：启动前动态执行 `fnm env`

适合你确实希望跟随 `.node-version` / `.nvmrc` 切换版本的场景。

示例：

```ini
[Service]
Type=simple
User=administrator
Group=administrator
WorkingDirectory=/home/administrator/projects/myapp
Environment="HOME=/home/administrator"
ExecStart=/usr/bin/env bash -lc 'eval "$(/home/linuxbrew/.linuxbrew/bin/fnm env --shell bash)"; fnm use --silent-if-unchanged >/dev/null; exec zread browse --host 0.0.0.0 --port 19681'
Restart=always
RestartSec=3s
```

这条线更灵活，但也更依赖 shell 包装和 `fnm` 本身的行为。

#### 方案 C：命令依赖 TTY 时，用 `script` 提供 PTY

少数 CLI 命令在普通终端里能正常工作，但放进 systemd 这种**无交互、无 TTY**环境后，会出现：

- 进程启动后立即退出
- `systemctl start` 返回成功，但端口没有监听
- `journalctl` 里看到 `status=0/SUCCESS`，同时 service 又不断 `Restart=always`

这类命令有时不是完全不能后台运行，而是**需要一个伪终端（PTY）**。

此时可以用 `/usr/bin/script` 包一层：

```ini
[Service]
Type=simple
User=administrator
Group=administrator
WorkingDirectory=/home/administrator/projects/myapp
Environment="HOME=/home/administrator"
Environment="PATH=/home/administrator/.local/share/fnm/node-versions/v24.11.0/installation/bin:/usr/local/bin:/usr/bin:/bin"
Environment="TERM=xterm-256color"
Environment="BROWSER=/bin/true"
ExecStart=/usr/bin/script -q -c "zread browse --host 0.0.0.0 --port 19681" /dev/null
Restart=always
RestartSec=3s
```

设计意图：

- `/usr/bin/script`：分配一个 PTY
- `-q`：静默模式
- `-c "..."`：执行真正的 CLI 命令
- `/dev/null`：不额外保留 typescript 输出文件
- `TERM=xterm-256color`：给依赖终端能力的程序一个基础终端类型
- `BROWSER=/bin/true`：避免这类“浏览/打开”命令真的去弹浏览器

这个方案是**兼容手段**，不是首选默认方案。

推荐优先级仍然是：

1. 原生命令本身就支持稳定的 `serve` / `server` / `daemon` 模式
2. 用稳定 `PATH` 或 `fnm env` 解决 Node / fnm 环境
3. 只有确认问题根因是“缺少 TTY”时，才上 `script -q -c '...' /dev/null`

#### 什么时候不该继续硬拗

如果一个 npm CLI 的命令语义更像：

- 打开浏览器
- 展示交互菜单
- 做一次性生成 / 导出
- 启动后立即退出，但后台可能短暂拉起别的东西

那它可能并不适合作为 systemd 常驻服务入口。

优先顺序建议是：

1. 看工具是否有明确的 `serve` / `server` / `daemon` 子命令
2. 如果没有，再评估是否应该换成静态文件服务、反向代理，或其他真正适合常驻的服务方案
3. 只有在充分验证后，才考虑用 `script -q -c '...' /dev/null` 这类 PTY 包装兼容手段

### 🧪 验证 npm / fnm 服务配置是否真的生效

不要只看 `systemctl start` 是否返回成功，至少还要一起检查：

```bash
systemctl status myapp.service --no-pager -l
journalctl -u myapp.service -n 100 --no-pager -l
ss -lntp '( sport = :19681 )'
curl -I http://127.0.0.1:19681
```

常见信号：

- `status=127`：通常是命令找不到，优先检查 `PATH` 和 `ExecStart=` 第一个程序
- `Active: activating (auto-restart)`：通常是进程启动后又退出了，不能只看“start 成功”
- `curl: (7) Failed to connect`：通常说明端口并没有真的监听
- `code=exited, status=0/SUCCESS` 但服务不断重启：通常说明命令是“一次性命令”，不是适合常驻的服务入口

### 🏷️ Service Type 类型

| Type | 说明 |
|------|------|
| `simple` | **默认值**，ExecStart 进程即主进程，前台运行 |
| `forking` | ExecStart 会 fork 出子进程后退出（传统守护进程） |
| `oneshot` | 执行一次性任务后退出，常配合 `RemainAfterExit=yes` |
| `notify` | 类似 simple，但服务会通过 `sd_notify()` 通知就绪 |
| `dbus` | 服务通过 D-Bus 通知就绪 |
| `idle` | 等待其他任务完成后才启动 |

### 🔄 Restart 重启策略

| 值 | 说明 |
|------|------|
| `no` | **默认**，不自动重启 |
| `on-success` | 仅正常退出时重启 |
| `on-failure` | 非零退出码、信号终止、超时、看门狗时重启 |
| `on-abnormal` | 信号终止或超时时重启 |
| `on-abort` | 未捕获信号终止时重启 |
| `always` | **总是重启**（除 `systemctl stop` 外） |

### 📎 常用依赖关系关键字

| 关键字 | 说明 |
|------|------|
| `Requires=` | 强依赖，目标失败则本 unit 也失败 |
| `Wants=` | 弱依赖，目标失败不影响本 unit（**推荐使用**） |
| `Requisite=` | 强依赖，目标未启动则本 unit 直接失败（不尝试启动） |
| `Conflicts=` | 冲突，不能同时运行 |
| `Before=` / `After=` | 排序依赖，控制启动顺序 |
| `PartOf=` | 反向依赖，目标重启/停止时本 unit 跟随 |

---

## 三、Timer — 定时任务（替代 crontab）

### 📝 Timer Unit 文件示例

```ini
# /etc/systemd/system/mybackup.timer
[Unit]
Description=Run backup daily

[Timer]
OnCalendar=*-*-* 02:00:00       # 每天凌晨2点
Persistent=true                  # 错过的运行在开机后补跑
AccuracySec=1min                 # 精度窗口
RandomizedDelaySec=30min         # 随机延迟，避免同时运行

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/mybackup.service
[Unit]
Description=Backup Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
```

### ⏰ OnCalendar 时间格式

| 表达式 | 含义 |
|--------|------|
| `*-*-* *:*:00` | 每分钟 |
| `*-*-* *:00:00` | 每小时整点 |
| `*-*-* 02:00:00` | 每天凌晨2点 |
| `*-*-* 02,14:00:00` | 每天2点和14点 |
| `*-*.1,15 02:00:00` | 每月1号和15号凌晨2点 |
| `Mon *-*-* 09:00:00` | 每周一上午9点 |
| `hourly` | 每小时（快捷方式） |
| `daily` | 每天（快捷方式） |
| `weekly` | 每周（快捷方式） |
| `monthly` | 每月（快捷方式） |
| `*:0/5` | 每5分钟 |

### Timer 管理命令

```bash
systemctl start mybackup.timer        # 启动定时器
systemctl enable mybackup.timer       # 开机自启
systemctl list-timers                 # 列出所有定时器
systemctl list-timers --all           # 包含不活跃的
systemd-analyze calendar "*-*-* 02:00:00"  # 验证日历表达式
```

用户级 timer 的命令形式相同，只是改为 `--user`：

```bash
systemctl --user start mybackup.timer
systemctl --user enable mybackup.timer
systemctl --user list-timers
journalctl --user -u mybackup.service -f
```

---

## 四、journalctl — 日志管理

### 📖 基础查看

| 操作 | 命令 |
|------|------|
| 查看本次启动的所有日志 | `journalctl -b` |
| 查看上次启动的日志 | `journalctl -b -1` |
| 查看指定启动编号的日志 | `journalctl -b <编号>` |
| 查看内核日志 | `journalctl -k` |
| 实时跟踪日志 | `journalctl -f` |
| 显示完整日志（不截断） | `journalctl --no-pager -l` |
| 只显示最新 N 条 | `journalctl -n 50` |
| 以 JSON 格式输出 | `journalctl -o json` |

### 🔍 过滤查询

| 操作 | 命令 |
|------|------|
| 按 **unit** 过滤 | `journalctl -u nginx.service` |
| 按 **多个 unit** 过滤 | `journalctl -u nginx -u mysql` |
| 按 **进程 PID** | `journalctl _PID=1234` |
| 按 **时间范围** | `journalctl --since "2024-01-01" --until "2024-01-02"` |
| 按相对时间 | `journalctl --since "1 hour ago"` |
| 按 **优先级** | `journalctl -p err` |
| 按 **可执行文件** | `journalctl /usr/bin/nginx` |
| 组合过滤 | `journalctl -u nginx --since today -p warning` |

### 📊 优先级（Priority）等级

| 等级 | 值 | 说明 |
|------|-----|------|
| emerg | 0 | 系统不可用 |
| alert | 1 | 必须立即处理 |
| crit | 2 | 严重情况 |
| err | 3 | 错误 |
| warning | 4 | 警告 |
| notice | 5 | 正常但重要 |
| info | 6 | 信息 |
| debug | 7 | 调试 |

> `journalctl -p err` 等价于 `journalctl -p 3`，会显示 0~3 级别。

### 🗑️ 日志维护

| 操作 | 命令 |
|------|------|
| 查看日志磁盘占用 | `journalctl --disk-usage` |
| 清理日志（保留最近2天） | `journalctl --vacuum-time=2d` |
| 清理日志（保留 100M） | `journalctl --vacuum-size=100M` |
| 清理日志（保留最近1000条） | `journalctl --vacuum-files=1000` |

> 长期日志存储配置在 `/etc/systemd/journald.conf` 中设置 `Storage=persistent`。

---

## 五、其他 systemd 工具

### 🔍 systemd-analyze

```bash
systemd-analyze                           # 查看启动耗时
systemd-analyze blame                     # 查看各服务启动耗时
systemd-analyze critical-chain            # 启动关键路径
systemd-analyze verify myapp.service      # 验证 unit 文件语法
systemd-analyze calendar "Mon *-*-* 09:00" # 验证日历表达式并显示下次触发时间
```

### 🖥️ hostnamectl / localectl / timedatectl / loginctl

```bash
hostnamectl set-hostname myserver         # 设置主机名
hostnamectl                               # 查看主机信息

localectl set-locale LANG=zh_CN.UTF-8    # 设置语言环境

timedatectl set-timezone Asia/Shanghai   # 设置时区
timedatectl set-ntp true                 # 启用 NTP 同步

loginctl list-sessions                   # 列出登录会话
loginctl terminate-session <id>          # 终止会话
```

---

## 六、Socket Activation — 按需启动

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My App Socket

[Socket]
ListenStream=0.0.0.0:8080

[Install]
WantedBy=sockets.target
```

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My App Service

[Service]
ExecStart=/usr/bin/myapp
User=myapp
```

```bash
systemctl enable --now myapp.socket   # 启用 socket（不是 service）
systemctl start myapp.socket           # socket 收到连接时自动拉起 service
```

---

## 七、快速排查故障

```bash
# 1. 查看服务状态
systemctl status <unit>

# 2. 查看详细失败信息
systemctl status <unit> -l

# 3. 查看服务日志
journalctl -u <unit> --since "10 min ago" --no-pager

# 4. 验证 unit 文件语法
systemd-analyze verify /etc/systemd/system/<unit>

# 5. 修改 unit 后重载
systemctl daemon-reload
systemctl restart <unit>

# 6. 查看服务的完整属性
systemctl show <unit>

# 7. 查看服务底层 unit 文件路径
systemctl cat <unit>
```

---

## 八、常用工作流速查

```bash
# 🆕 创建一个新服务（完整流程）
sudo vim /etc/systemd/system/myapp.service    # 1. 编写 unit 文件
sudo systemctl daemon-reload                   # 2. 重载配置
sudo systemctl start myapp                     # 3. 启动测试
sudo systemctl status myapp                    # 4. 检查状态
sudo systemctl enable myapp                    # 5. 设置开机自启
journalctl -u myapp -f                         # 6. 查看实时日志

# ✏️ 修改已有服务
sudo systemctl edit myapp --full               # 编辑（自动 daemon-reload）
# 或者
sudo vim /etc/systemd/system/myapp.service
sudo systemctl daemon-reload
sudo systemctl restart myapp

# 🔄 创建 drop-in 覆盖（不修改原文件）
sudo systemctl edit myapp                      # 创建 /etc/systemd/system/myapp.service.d/override.conf
```

```bash
# 👤 创建一个新的用户服务（完整流程）
mkdir -p ~/.config/systemd/user
vim ~/.config/systemd/user/my-agent.service    # 1. 编写 user unit
systemctl --user daemon-reload                 # 2. 重载用户级配置
systemctl --user start my-agent                # 3. 启动测试
systemctl --user status my-agent               # 4. 检查状态
systemctl --user enable my-agent               # 5. 设置用户级自启
journalctl --user -u my-agent -f               # 6. 查看实时日志

# 如需退出登录后继续运行，再启用 lingering
sudo loginctl enable-linger "$USER"
```

---

> 💡 **提示**：大多数 `systemctl` 命令支持 Tab 补全，安装 `bash-completion` 包即可使用。
