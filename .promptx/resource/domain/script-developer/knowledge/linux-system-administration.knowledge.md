<knowledge>
  <concept>
    - **Linux发行版**: 如Ubuntu, CentOS, Debian, Fedora等。
    - **文件系统**: ext4, XFS, Btrfs等，以及文件系统层次标准 (FHS)。
    - **用户和组管理**: 用户账户、组、UID、GID、权限。
    - **进程管理**: 进程、线程、PID、PPID、僵尸进程、守护进程。
    - **服务管理**: Systemd, SysVinit, Upstart。
    - **软件包管理**: apt, yum, dnf, rpm。
    - **网络配置**: IP地址、子网掩码、网关、DNS、端口。
    - **日志管理**: rsyslog, journald。
    - **内核**: Linux操作系统的核心。
  </concept>
  <skill>
    - **安装和配置**: 安装Linux发行版，配置网络、用户、服务。
    - **文件和目录操作**: `ls`, `cd`, `pwd`, `mkdir`, `rm`, `cp`, `mv`, `find`, `grep`。
    - **权限管理**: `chmod`, `chown`, `umask`。
    - **用户和组管理**: `useradd`, `usermod`, `userdel`, `groupadd`, `groupmod`, `groupdel`, `passwd`。
    - **进程和服务管理**: `ps`, `top`, `htop`, `kill`, `systemctl`, `service`。
    - **软件包管理**: `apt install`, `yum update`, `dpkg`, `rpm`。
    - **磁盘管理**: `df`, `du`, `fdisk`, `mkfs`, `mount`。
    - **网络配置**: `ip addr`, `ifconfig`, `route`, `netstat`, `ss`, `firewalld`, `iptables`。
    - **日志分析**: `journalctl`, `tail`, `cat`, `grep`。
    - **计划任务**: `cron`, `at`。
    - **SSH**: 远程登录和文件传输。
  </skill>
  <tool>
    - **Bash/Zsh**: 命令行Shell。
    - **Vim/Nano**: 文本编辑器。
    - **Systemd**: 服务管理器。
    - **Docker/Podman**: 容器化技术。
    - **Ansible/Puppet/Chef**: 配置管理工具。
    - **Nagios/Zabbix**: 监控工具。
  </tool>
  <best-practice>
    - **最小化安装**: 只安装必要的软件包。
    - **定期更新系统**: 保持系统和软件包最新。
    - **使用SSH密钥认证**: 禁用密码登录。
    - **配置防火墙**: 限制不必要的端口访问。
    - **定期备份数据**。
    - **监控系统资源**: CPU, 内存, 磁盘, 网络。
    - **使用版本控制管理配置文件**。
    - **遵循最小权限原则**。
  </best-practice>
</knowledge>