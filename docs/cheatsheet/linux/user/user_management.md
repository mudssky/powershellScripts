# Linux 用户管理速查表

## 概览
- 关键文件：`/etc/passwd`、`/etc/shadow`、`/etc/group`、`/etc/skel`
- 常用工具：`adduser`、`useradd`、`usermod`、`userdel`、`passwd`、`groupadd`、`gpasswd`、`id`、`groups`
- 推荐：优先使用交互友好的 `adduser`（Debian/Ubuntu）；批量/脚本用 `useradd`

## 基本查询
- 当前身份：`id`、`whoami`
- 查看用户：`getent passwd`、`getent passwd 用户名`
- 查看组：`getent group`、`getent group 组名`
- 查看附属组：`groups 用户名`

## 创建用户
- 交互创建（含家目录与初始配置）：
  - `sudo adduser alice`
- 非交互创建（更可控）：
  - `sudo useradd -m -s /bin/bash -c "Alice" alice`
  - 设置密码：`echo 'alice:StrongPass' | sudo chpasswd`
- 指定主组与附属组：
  - 主组：`sudo useradd -m -g developers alice`
  - 附属组：`sudo usermod -aG docker,sudo alice`
- 使用 `/etc/skel` 模板：自动复制默认文件到家目录

## 修改与删除
- 修改登录 shell：`sudo chsh -s /bin/zsh alice`
- 修改家目录/注释等：`sudo usermod -m -d /home/alice alice`、`sudo usermod -c "Alice Dev" alice`
- 删除用户：
  - 保留家目录：`sudo userdel alice`
  - 删除家目录：`sudo userdel -r alice`

## 组管理
- 新建组：`sudo groupadd developers`
- 删除组：`sudo groupdel developers`
- 重命名：`sudo groupmod -n devs developers`
- 管理组成员：
  - 加入：`sudo gpasswd -a alice developers`
  - 移除：`sudo gpasswd -d alice developers`

## Sudo 权限
- 编辑规则：`sudo visudo`（安全检查）；或在 `/etc/sudoers.d/` 新增片段
- 常用示例：
  - 允许组免密执行特定命令：
    - `%deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp`
  - 只允许某命令：
    - `alice ALL=(ALL) /usr/bin/journalctl -u myapp`
- 最小权限原则：只授予必要命令，避免 `ALL` 与通配符

## 账号安全与生命周期
- 锁定/解锁：`sudo passwd -l alice`、`sudo passwd -u alice`
- 过期策略：`sudo chage -E 2026-01-01 alice`、`sudo chage -M 90 -W 7 alice`
- 禁用登录：`sudo usermod -s /usr/sbin/nologin alice`
- 强密码策略：使用 PAM（如 `pam_pwquality`）与系统策略

## 会话与审计
- 在线用户：`who`、最近登录：`last`、从不登录：`lastlog`
- SSH 日志：`journalctl -u ssh -e`、失败登录统计：`faillog -a`
- 变更审计（建议）：`auditd` 基线配置与规则

## 常见问题排查
- 家目录权限错误：`sudo chown -R alice:alice /home/alice`；`chmod 700 /home/alice`
- SSH 登录失败：检查 `~/.ssh` 权限（目录 700，文件 600）、`AuthorizedKeysFile` 设置
- shell 不存在：`which bash`/`zsh`，确认 `/etc/shells` 中存在
- PATH 异常：检查 `/etc/profile`、`~/.profile`、`~/.bashrc`，以及 `umask` 设置

## 参考
- 相关文档：`../env.md`（环境变量）、`../apt.md`（包管理）