# Linux 开发服务器最佳实践速查表

## 目标
- 构建稳定、安全、可维护的开发服务器基线
- 提供最小权限、自动化更新、可观测性与便捷远程开发

## 安全基线
- 仅密钥登录：`/etc/ssh/sshd_config` → `PasswordAuthentication no`、`PermitRootLogin no`
- 端口与防火墙：`ufw default deny`、仅开放必要端口；或使用 `nftables`
- 防爆破：`fail2ban`（监控 SSH 日志、合理的 ban 策略）
- 自动更新：`unattended-upgrades`（安全更新自动安装，邮件通知）
- 系统时间与日志：启用 `systemd-timesyncd`；`journalctl` 与 `logrotate` 配置

## 系统与包管理
- 选择发行版：优先 LTS（如 Ubuntu LTS）
- 基础包：`build-essential`、`curl`、`git`、`htop`/`btop`、`vim`/`neovim`
- 本地化：时区 `timedatectl set-timezone`、Locale 统一（避免构建差异）
- 磁盘与健康：`smartctl`、`df -h`、`du -sh`、inode 与日志占用监控
- 参考：`../env.md`、`../apt.md`

## 用户与权限
- 分层用户：管理员（sudo）、普通开发、CI/服务用户（受限权限）
- 最小权限：`sudoers` 精细化（使用 `/etc/sudoers.d/`），拒绝 `ALL`
- 目录与权限：统一 umask；共享目录使用 setgid 与组策略；敏感目录使用 `chattr +i`

## 运行时与容器
- Node：`nvm` 管理多版本；默认使用 LTS；隔离项目 node_modules
- Python：`pyenv`+`venv`；避免系统 Python 污染
- Rust：`rustup`（稳定工具链）
- 容器：优先 rootless（`podman`）或限制权限的 `docker`；最小镜像，固定 tag
- 私有仓库与拉取策略：凭据管理、镜像扫描、网络策略（代理/出口控制）

## 部署与服务管理（systemd）
- 单元文件规范：指定用户、工作目录、环境变量、Restart 策略（如 `on-failure`）
- 健康检查：使用 `ExecStartPre`、`ExecStartPost` 与 `ExecReload`；失败告警
- 日志：`StandardOutput=journal`，结合 `journalctl -u service -f`
- 回滚与灰度：保留旧版本、分批更新、反向代理路由控制（见 `caddy/`）

## 网络与代理
- 反向代理：`Caddy`/`Nginx`（证书自动管理、限速、缓存）
- SSH 隧道：临时开放内部端口；跨网络安全访问
- DNS/hosts：统一命名策略（如 `dev-<team>-<service>`）

## 监控与日志
- 资源监控：`node_exporter` + Prometheus；基础报警（CPU、内存、磁盘、负载）
- 日志聚合：集中化（如 Loki/ELK）；应用日志标准化（JSON、结构化）
- 追踪与指标：OpenTelemetry 基线（采样、导出）

## 远程开发与效率
- VS Code Remote SSH；`tmux` 会话复用；`fzf`、`zoxide`、`ripgrep` 快速检索
- 包管理与脚本：统一脚本目录，避免手工命令分散与漂移
- 代理与网络：必要时配置开发代理（如 Clash），分流策略与白名单

## 备份与恢复
- 配置与数据分层备份：`/etc`、应用配置、数据库与持久化目录
- 备份策略：定期/保留周期、异地/跨账户；恢复演练（文档化步骤）

## 快速检查清单
- [ ] SSH 仅密钥、禁 root；`ufw`/`fail2ban` 生效
- [ ] 自动安全更新启用，系统时间同步
- [ ] 用户分层与最小权限；共享目录权限有明确策略
- [ ] 运行时通过 `nvm`/`pyenv`/`rustup` 管理；容器 rootless/最小镜像
- [ ] 部署以 systemd 管理，日志结构化；具备回滚与灰度能力
- [ ] 监控与报警基线就绪；备份策略可演练

## 参考
- 相关文档：`../env.md`、`../apt.md`、`../server/caddy/caddy.md`、`../server/caddy/静态站点最佳实践.md`