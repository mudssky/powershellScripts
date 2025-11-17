## 目标
- 在 `c:\home\env\powershellScripts\docs\cheatsheet\linux` 下新增 3 篇 Cheatsheet：
  1) 用户管理
  2) 权限与 ACL/Capabilities 管理
  3) Linux 作为开发服务器的最佳实践
- 维持现有目录命名风格（英文目录、文件名可中英文混用），与已存在的 `network/`、`server/` 等结构保持一致。

## 目录与文件结构
- `linux/user/user_management.md`
- `linux/permission/permission_management.md`
- `linux/server/development_server_best_practices.md`

## 文档内容大纲

### 1) 用户管理（`user_management.md`）
- 基本概念：`/etc/passwd`、`/etc/shadow`、`/etc/group`、登录 shell、home 目录、`/etc/skel`
- 用户增删改查：`adduser` vs `useradd`、`passwd`、`usermod`、`userdel`、批量创建策略
- 组管理：`groupadd`、`groupdel`、`groupmod`、`gpasswd`、主组/附属组、`id`/`groups`
- 账号安全：锁定/解锁 `passwd -l/-u`、过期策略 `chage`、禁用登录 shell、强密码策略（PAM 简述）
- Sudo 管理：`visudo`、`/etc/sudoers`、`/etc/sudoers.d/`、最小权限原则、常见规则示例
- 会话与审计：`who`、`last`、`lastlog`、`journalctl -u ssh`、`faillog`、失败登录排查
- 常见排错：家目录权限错误、shell 不存在、`nologin`、`PATH` 问题

### 2) 权限与 ACL/Capabilities 管理（`permission_management.md`）
- 权限模型：拥有者/组/其他，读写执行；符号/八进制表示法
- 权限命令：`chmod`、`chown`、`chgrp`、`umask`（持久化到 shell 配置）
- 特殊位：setuid、setgid、sticky；`find -perm` 检查
- ACL：`getfacl`/`setfacl`、默认 ACL、与传统权限的关系与优先级
- 文件属性：`chattr`/`lsattr`（不可变等）
- Linux Capabilities：`getcap`/`setcap`，最小权限替代 setuid 的场景
- 安全域：SELinux/AppArmor 概览、查看/调整模式的基本命令与排错思路
- SSH/服务文件权限：`~/.ssh` 目录与文件权限、`systemd` 单元文件权限建议

### 3) 开发服务器最佳实践（`development_server_best_practices.md`）
- 基础选择：发行版（Ubuntu LTS 等）、时区/Locale、主机名约定
- 安全基线：仅密钥登录、禁用 root 登录、端口与 `ufw`/`nftables`、`fail2ban`、自动更新 `unattended-upgrades`
- 用户与 sudo：分层用户、最小权限、`sudoers` 规范、审计策略
- 包与环境：`apt` 基本流程、`logrotate` 与 `journald`、`timesyncd`/NTP、磁盘与日志容量监控
- 运行时栈：Node（`nvm`）、Python（`pyenv`/venv）、Rust（`rustup`）、容器（`docker`/rootless `podman`）
- 部署与服务：`systemd` 单元编写规范、健康检查、回滚策略、灰度发布思路
- 网络与代理：SSH 隧道、反向代理（与已有 `server/caddy/` 相关）、内网访问策略
- 远程开发：`OpenSSH` + VS Code Remote、`tmux`、常用终端工具（与 `terminal/` 目录呼应：`fzf`/`zoxide`）
- 监控与告警：`node_exporter` + Prometheus 基线、备份策略与恢复演练

## 与现有文档的关联
- 参考并交叉链接：`linux/apt.md`（包管理）、`linux/env.md`（环境与变量）、`linux/server/caddy/*`（反向代理/静态站点）
- 保持术语与命令风格一致，命令示例使用简洁、直接可复制的形式。

## 交付方式
- 创建上述目录与文件，并填充内容（中文为主，命令与路径保持英文）
- 每篇文档以“速查表”结构呈现：概念简述 + 常用命令块 + 注意事项/坑点 + 示例
- 在 `linux/` 下不改动现有文件命名，新增独立文档便于模块化维护

## 验收标准
- 目录结构按计划创建；3 篇文档均完成初版并可直接使用
- 每篇至少包含：核心概念、10+ 常用命令示例、常见错误与排错建议
- 与现有相关文档有明确交叉链接；风格统一、便于快速阅读复制

## 后续维护建议
- 根据团队使用场景追加发行版差异章（如 Debian/AlmaLinux）
- 将高频命令整合为脚本片段（未来可迁移到 `scripts/`）
- 定期安全基线复盘与更新（SSH、防火墙、容器根less 化推进）