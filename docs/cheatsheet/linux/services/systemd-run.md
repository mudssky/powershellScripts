
`systemd-run` 是一个非常强大的工具，它允许你将普通的命令封装成**临时的 (transient)** systemd 单元（Service、Scope 或 Timer）来运行。这对于后台运行任务、限制资源使用（CPU/内存）、定时执行以及与终端会话解绑非常有用。

---

### 🚀 1. 基础用法

最简单的用法，将命令作为后台服务运行（自动生成随机的 Unit 名称）：

```bash
sudo systemd-run <command> [args...]
# 示例：
sudo systemd-run updatedb
```

**在当前终端前台运行 (Scope 模式)**
不放到后台，而是将其作为一个 Scope 运行（常用于对当前前台进程限制资源）：

```bash
sudo systemd-run --scope <command>
```

**打开一个完全隔离的交互式 Shell**
分配伪终端 (PTY) 并且独立于当前登录会话（防止 SSH 断开导致任务终止）：

```bash
sudo systemd-run --pty --same-dir -t /bin/bash
```

---

### 🏷️ 2. 命名与描述

如果不指定名称，系统会生成类似 `run-r12345.service` 的名字。为了方便后续管理和查看日志，**强烈建议指定名称**。

```bash
sudo systemd-run --unit=my-backup-task \
                 --description="Daily Database Backup" \
                 /usr/local/bin/backup.sh
```

*执行后，你可以通过 `systemctl status my-backup-task` 来查看它。*

---

### ⏳ 3. 阻塞等待与自动清理

默认情况下，`systemd-run` 会立即返回。如果你希望等待任务执行完毕，并获取其退出状态码：

```bash
# --wait 会阻塞当前终端，直到任务完成
sudo systemd-run --unit=my-task --wait /bin/sleep 5
```

如果加上 `--collect`，任务结束后对应的临时 unit 会被系统立即清理回收，不会在 `systemctl` 列表中留下处于 "dead" 状态的记录：

```bash
sudo systemd-run --collect --unit=my-task /bin/sleep 5
```

---

### 🛡️ 4. 资源限制 (Cgroups)

这是 `systemd-run` 最强大的功能之一，利用 Cgroups 限制命令可使用的资源：

**限制内存使用量 (超过将被 OOM 杀死):**

```bash
sudo systemd-run --scope -p MemoryMax=500M <command>
```

**限制 CPU 使用率 (最高占用单核的 50%):**

```bash
sudo systemd-run --scope -p CPUQuota=50% <command>
```

**限制 IO 权重 (降低后台任务对磁盘读写的影响):**

```bash
sudo systemd-run -p IOWeight=10 <command>
```

*注：`-p` 是 `--property=` 的简写。*

---

### ⏰ 5. 定时任务 (替代 Cron 或 at)

`systemd-run` 可以即时创建临时的 timer unit。

**延迟执行 (类似 `at` 命令):**

```bash
# 5分钟后执行
sudo systemd-run --on-active="5m" --unit=delayed-job /bin/echo "Hello"
```

**特定时间执行:**

```bash
# 在特定的时间点执行
sudo systemd-run --on-active="2024-12-31 23:59:00" /bin/echo "Happy New Year"
```

**周期性执行 (类似 Cron):**

```bash
# 每天凌晨 2 点执行
sudo systemd-run --on-calendar="*-*-* 02:00:00" /usr/local/bin/daily-sync.sh
```

---

### 👤 6. 用户与权限控制

**指定以特定系统用户身份运行:**

```bash
sudo systemd-run --uid=www-data --gid=www-data /bin/script.sh
```

**作为普通用户运行（User systemd）:**
不需要 `sudo`，任务由用户的 systemd 实例管理（注销后只要启用了 lingering 也可以继续运行）：

```bash
systemd-run --user --unit=my-user-task /bin/echo "Running as standard user"
```

---

### 环境变量与工作目录

**设置环境变量:**

```bash
sudo systemd-run --setenv=FOO=bar --setenv=ENV=prod /bin/script.sh
```

**指定工作目录:**

```bash
sudo systemd-run --working-directory=/var/www/html /bin/script.sh
```

---

### 🔍 7. 管理与日志查看

假设你使用了 `--unit=my-task` 运行了一个任务：

**查看状态:**

```bash
systemctl status my-task
# 或者针对普通用户：
systemctl --user status my-task
```

**停止正在运行的任务:**

```bash
sudo systemctl stop my-task
```

**查看任务的输出/日志:**
systemd-run 运行的命令，其标准输出 (stdout) 和错误 (stderr) 会自动重定向到 Journal。

```bash
# 查看该任务的所有日志
journalctl -u my-task

# 持续滚动跟踪日志
journalctl -u my-task -f
```

---

### 💡 实用组合技 (Pro Tips)

**1. "防断网"后台下载（完美替代 `nohup ... &` 和 `tmux`）：**

```bash
systemd-run --user --unit=download-ubuntu \
            --remain-after-exit \
            wget https://releases.ubuntu.com/22.04/ubuntu-22.04.4-desktop-amd64.iso
```

*你可以随时关闭终端回家，之后只需运行 `journalctl --user -u download-ubuntu -f` 即可查看下载进度。*

**2. 跑一个限制资源、指定目录和用户的后台脚本，并收集日志：**

```bash
sudo systemd-run --unit=heavy-data-process \
                 --working-directory=/data \
                 --uid=data_user \
                 -p CPUQuota=200% \
                 -p MemoryMax=4G \
                 python3 process.py
```
