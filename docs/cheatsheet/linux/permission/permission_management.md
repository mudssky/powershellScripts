# Linux 权限与 ACL/Capabilities 速查表

## 概览
- 权限层级：拥有者（user）/组（group）/其他（other）
- 表示法：符号（`u/g/o`、`r/w/x`）与八进制（`chmod 640`）
- 扩展机制：ACL（细粒度用户/组权限）、Capabilities（可替代部分 setuid）

## 基本权限
- 查看权限：`ls -l`、`namei -l 路径`
- 修改权限：
  - 符号法：`chmod u=rw,g=r,o=--- file`
  - 八进制：`chmod 640 file`
- 拥有者与组：`chown alice:developers file`、`chgrp developers file`
- 默认权限：`umask`（临时：`umask 027`；持久化：写入 `~/.profile` 或 `/etc/profile`）

## 特殊位
- setuid：可执行文件以文件拥有者身份运行（安全风险）
- setgid：目录使新建文件继承目录组；可执行以组身份运行
- sticky：目录中只有文件拥有者可删除（如 `/tmp`）
- 检查/设置：
  - 八进制高位：`chmod 4755 file`（4=setuid，2=setgid，1=sticky）
  - 符号位：`chmod u+s file`、`chmod g+s dir`、`chmod +t dir`
- 搜索特殊权限：`find / -perm -4000 -type f -exec ls -l {} +`（审计 setuid）

## ACL（访问控制列表）
- 查看：`getfacl file`
- 赋予特定用户/组：
  - `setfacl -m u:alice:rw file`
  - `setfacl -m g:developers:r file`
- 默认 ACL（目录对子文件生效）：`setfacl -m d:u:alice:rwX dir`
- 删除条目：`setfacl -x u:alice file`
- 清空 ACL：`setfacl -b file`
- 注意：ACL 与传统权限共同作用，优先匹配具体条目

## 文件系统属性（`chattr`/`lsattr`）
- 不可变：`sudo chattr +i file`（即使 root 也不可更改/删除）
- 只追加：`sudo chattr +a logfile`（仅允许追加写入）
- 查看：`lsattr file`
- 适用：ext 系列文件系统

## Linux Capabilities
- 查看：`getcap /path/to/bin`
- 赋予：`sudo setcap cap_net_bind_service=+ep /usr/local/bin/myapp`
- 场景：允许非 root 绑定低端口等，替代 setuid 的部分需求
- 清除：`sudo setcap -r /usr/local/bin/myapp`

## SELinux / AppArmor（概览）
- 模式查看：
  - SELinux：`getenforce`、`sestatus`
  - AppArmor：`aa-status`
- 切换（临时/持久化需谨慎）：`setenforce 0/1`
- 审计排错：查看相关日志（`/var/log/audit/audit.log` 或 `journalctl`）

## SSH 与系统配置文件的权限建议
- `~/.ssh`：目录 `700`、`authorized_keys` `600`、`config` `600`
- systemd 单元：`/etc/systemd/system/*.service` 保持 root 可写，应用目录最小权限
- 私密配置：使用最小可读原则，避免组/其他可读

## 常见排错
- 权限不足但 ACL 生效：确认 ACL 条目与默认 ACL 是否覆盖
- setuid/setgid 异常：检查挂载选项与安全策略是否屏蔽
- Capabilities 无效：确认文件系统/内核支持、二进制是否符合要求

## 参考
- 相关文档：`../env.md`（环境与变量）、`../apt.md`（包管理）