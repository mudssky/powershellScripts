# FNOS Mount Manager

这套工具用于管理 FNOS / Linux 上的外接数据盘挂载配置。

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

# 执行统一修复
bash linux/fnos/fnos-mount-manager/fnos-mount-manager.sh repair
```

## 迁移说明

- `linux/fnos/remount.sh` 已被统一管理器取代，不再作为独立入口保留。
- 旧的 `force-remount-disks.service`、登录 shell 里的 `mount -a` 等遗留逻辑，应通过 `check` 找出后手工清理或用 `repair --force` 处理边界明确的 systemd 项。
