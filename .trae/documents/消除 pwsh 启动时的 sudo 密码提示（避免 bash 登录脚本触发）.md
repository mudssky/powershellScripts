## 现象与成因

* 启动 `pwsh` 出现 `[sudo] password` 与 NTFS 报错，来源于系统正在尝试挂载 NTFS 分区而该分区被独占或已被其它服务自动挂载。

* 你的 fstab 行：`linux/fnos/fstab:7` 使用 `ntfs` 与 `x-systemd.automount`，在桌面环境（udisks2/GVFS）也会自动挂载到 `/media/<user>/<Label>` 的情况下，容易发生“重复挂载”冲突。

* Windows 快速启动/休眠会让 NTFS 处于“未干净卸载”状态，`ntfs-3g` 会拒绝以读写方式挂载，提示用 `fuser` 查占用。

## 修复目标

* 消除重复挂载导致的错误与密码提示。

* 保留按需自动挂载能力，避免影响开机流程。

* 合理的权限与安全设置（不使用 `umask=000` 的全开放权限）。

## 调整方案

1. 防重复挂载：

   * 将 fstab 改为按需自动挂载的推荐组合：`noauto,x-systemd.automount`（加 `noauto`，避免开机强制挂载，与 automount 触发访问时挂载配合）。

   * 移除 `users`（常用于允许普通用户手动挂载/卸载；与 automount/桌面自动挂载混用更易引起二次挂载与授权混乱）。
2. 权限与编码：

   * 使用 `uid=1000,gid=1000,umask=022`（常见的更安全默认），必要时 `iocharset=utf8`、`windows_names`（避免不合法文件名），`big_writes`（性能优化）。
3. Hibernation/独占修复：

   * 若仍提示独占：确认 Windows 关闭“快速启动”，进行完全关机；或临时用 `ro` 挂载；最后手段用 `remove_hiberfile`（会删除休眠文件，需谨慎）。

## 建议的 fstab 行示例

* `UUID=1CB866F3B866CB3A /vol00/galDisk ntfs nofail,noauto,x-systemd.automount,x-systemd.device-timeout=60,uid=1000,gid=1000,umask=022,iocharset=utf8,windows_names,big_writes 0 0`

## 验证步骤

* 确认挂载点存在：`/vol00/galDisk`。

* 禁用桌面自动挂载或确保该设备不再被自动挂载到 `/media/...`。

* 重载守护并测试按需挂载：访问 `ls /vol00/galDisk` 后检查 `mount | grep galDisk`；不应再出现密码提示和冲突报错。

## 风险与回滚

* 若桌面仍自动挂载导致冲突，需在桌面设置关闭“自动挂载外部设备”或编写 udev/udisks 规则忽略该设备。

* 如需回滚，恢复旧的 fstab 行并重启。

