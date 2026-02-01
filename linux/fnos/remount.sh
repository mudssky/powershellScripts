#!/bin/bash

# 定义 UUID 和挂载点名称映射
declare -A disks
disks=(
    ["36A60099A6005BAD"]="animeDisk"
    ["2C702BFA702BC982"]="bookDisk"
    ["CE54A9E254A9CD91"]="debutDisk"
    ["1CB866F3B866CB3A"]="galDisk"
    ["F26663D26663965F"]="RemovableDisk"
)

echo "Starting force remount..."

for uuid in "${!disks[@]}"; do
    name="${disks[$uuid]}"
    dev="/dev/disk/by-uuid/$uuid"
    mountpoint="/vol00/$name"
    # systemd unit name for /vol00/name is vol00-name.mount
    unit="vol00-$name"

    echo "----------------------------------------"
    echo "Processing $name (UUID: $uuid)..."
    
    # 停止 systemd 服务以防止干扰
    # 注意：如果 fstab 配置了 x-systemd.automount，停止服务是必要的，否则 mount 可能被拒绝
    sudo systemctl stop "${unit}.automount" 2>/dev/null
    sudo systemctl stop "${unit}.mount" 2>/dev/null
    
    # 杀掉占用该设备的进程
    # realpath 可以解析 /dev/disk/by-uuid/... 到 /dev/sdX
    real_dev=$(realpath "$dev" 2>/dev/null)
    if [ -n "$real_dev" ] && [ -e "$real_dev" ]; then
        if sudo fuser "$real_dev" >/dev/null 2>&1; then
            echo "Killing processes on $real_dev..."
            sudo fuser -k -9 "$real_dev"
        fi
    fi
    
    # 确保挂载点存在
    if [ ! -d "$mountpoint" ]; then
        echo "Creating mountpoint $mountpoint..."
        sudo mkdir -p "$mountpoint"
    fi

    # 挂载 (利用 fstab 配置)
    echo "Mounting $mountpoint..."
    sudo mount "$mountpoint"
    
    if mountpoint -q "$mountpoint"; then
        echo "✅ $name mounted successfully."
    else
        echo "❌ Failed to mount $name."
        # 尝试再次挂载并显示错误信息
        sudo mount -v "$mountpoint"
    fi
done

echo "----------------------------------------"
echo "All done. Current status:"
lsblk -o NAME,FSTYPE,LABEL,UUID,MOUNTPOINTS
