# FNOS Mount Manager

这套工具用于管理 FNOS / Linux 上的外接数据盘挂载配置。

当前方案接受 FNOS 可能先把磁盘挂到型号路径这一事实，再在其上叠加稳定的业务名访问层：

- 型号路径仍然保留，作为底层真实挂载位置。
- 业务名路径是推荐访问入口，也是后续 Samba/shared path 应优先引用的路径。
- 重启后若出现“已挂错路径”或“未挂上”的混合状态，默认入口是 `reconcile`，而不是 `repair` / `remount`。

## 配置文件

- `linux/fnos/fnos-mount-manager/disks.example.conf`: 仓库内可提交的示例配置
- `linux/fnos/fnos-mount-manager/disks.local.conf`: 当前机器的私有配置
- `linux/fnos/fnos-mount-manager/fstab.example`: 从示例配置生成的受控挂载区块预览
- `linux/fnos/fnos-mount-manager/fstab`: 从本机私有配置生成的受控挂载区块预览
- `linux/fnos/fnos-mount-manager/tmpfiles.example.conf`: 从示例配置生成的目录创建规则预览
- `linux/fnos/fnos-mount-manager/tmpfiles.conf`: 从本机私有配置生成的目录创建规则预览

不要手改 `fstab.example`、`fstab`、`tmpfiles.example.conf` 或 `tmpfiles.conf`。这些文件都是生成产物。

## 构建

```bash
bash linux/fnos/fnos-mount-manager/build.sh
```

构建后会得到两个单文件脚本：

- `bin/fnos-mount-manager`
- `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh`

## 常用命令

### 基础配置与诊断层

```bash
# 生成 example/local 的挂载区块预览
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh generate

# 检查配置、漂移和已知冲突来源
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh check

# 查看当前挂载状态
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh status

# 应用到 system fstab
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh apply

# 写到其他目标文件，便于测试或 dry-run
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh apply --target /tmp/fstab.test
```

### 启动后协调层

```bash
# 安装并启用开机 reconcile service
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh install-reconcile-service

# 安装后立刻执行一次开机 service
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh install-reconcile-service --start-now

# 为已被 FNOS 挂到型号路径的磁盘建立业务名 bind alias
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh alias

# 只补挂当前仍未挂上的磁盘
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh backfill

# 默认重启后入口：先同步 alias，再补挂失败盘
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh reconcile
```

### 保守修复与手工接管层

```bash
# 执行统一保守修复，不主动接管已挂到其他路径的磁盘
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh repair

# 手工接管：把被 FNOS 挂到型号路径的磁盘卸载后重挂回业务名路径
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh remount
```

建议的运维心智：

- `generate` / `apply` / `check` / `status` 负责配置、预览和观测。
- `install-reconcile-service` 用来注册默认的开机协调入口。
- `alias` / `backfill` / `reconcile` 负责重启后的协调。
- `repair` 是保守修复工具，只在挂载缺失或 unit 状态异常时使用。
- `remount` 是显式接管工具，会扰动底层真实挂载，不应作为默认重启后入口。

## 迁移说明

- `linux/fnos/remount.sh` 已被统一管理器取代，不再作为独立入口保留。
- 旧的 `force-remount-disks.service`、登录 shell 里的 `mount -a` 等遗留逻辑，应通过 `check` 找出后手工清理或用 `repair --force` 处理边界明确的 systemd 项。
- `tmpfiles` 规则不要移除。`/etc/tmpfiles.d/fnos-mount-manager.conf` 仍负责确保业务名挂载点目录存在，它和 `reconcile` service 不是重复关系。
- 若机器上仍有旧的 `force-remount-disks.service`，应移除或停用；`install-reconcile-service` 在检测到它仍指向旧脚本时会自动停用。
- 当业务名路径已经稳定后，Samba 或其他共享配置应优先把 `path` 指向业务名路径，而不是 FNOS 自动生成的型号路径。
