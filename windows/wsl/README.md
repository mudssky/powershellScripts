# WSL 全局配置

`%UserProfile%\.wslconfig` 控制当前 Windows 用户的所有 WSL 2 发行版。本目录的模板只声明项目有意偏离 WSL 默认行为的设置；资源限制和已符合预期的默认项保持省略，以便配置随宿主机和 WSL 版本自适应。

`.wslconfig` 仅影响 WSL 2，并要求 Windows build 19041 或更高版本。下文的 mirrored 网络及相关实验设置还有更高的版本要求。

## 省略项及默认值

下表依据 Microsoft WSL 文档核对于 2026-09-05。默认值可能随 WSL 版本变化，升级 WSL 后应以最新官方文档为准。

| 设置 | 当前默认值 | 省略后的行为 |
| --- | --- | --- |
| `memory` | Windows 物理内存的 50% | 作为 WSL 2 VM 的内存上限，内存仍按需使用 |
| `processors` | Windows 的全部逻辑处理器 | 不再固定为某个 CPU 数量 |
| `swap` | Windows 物理内存的 25%，向上取整到 GB | swap 大小随宿主机内存调整 |
| `localhostForwarding` | `true` | NAT 模式下把绑定 wildcard/localhost 的 WSL 端口映射到 Windows localhost；mirrored 模式会忽略此设置 |
| `guiApplications` | `true` | 支持 WSLg GUI 应用 |
| `nestedVirtualization` | `true` | 允许 WSL 2 内使用嵌套虚拟化 |
| `dnsTunneling` | `true` | 通过虚拟化通道向 Windows 转发 DNS 请求 |
| `firewall` | `true` | 应用 Windows 和 Hyper-V 防火墙规则 |
| `autoProxy` | `true` | WSL 使用 Windows 的 HTTP 代理信息 |
| `autoMemoryReclaim` | `dropCache` | 自动立即回收 Linux 页缓存并归还 Windows；不再固定为较缓慢的 `gradual` |

例如，32 GB 内存的宿主机默认允许 WSL 使用最多约 16 GB 内存，并创建约 8 GB swap；64 GB 宿主机则约为 32 GB 和 16 GB。它们是上限或容量，不代表 WSL 启动后会立即占用这些内存。

已有发行版的 swap VHD 可能保留此前创建的容量；省略 `swap` 表示后续不再由本项目固定其大小，并不承诺 WSL 会立即重建或调整现有 swap 文件。

## 项目保留的非默认设置

### `networkingMode=mirrored`

WSL 默认使用 `NAT`。mirrored 模式把 Windows 的网络接口镜像到 Linux，改善 VPN、IPv6、组播、局域网访问，以及 Windows 与 WSL 之间的 localhost 互通。部分依赖 NAT 地址或端口转发模型的旧脚本可能需要调整。

此模式要求 Windows 11 22H2 或更高版本。安装清单以 build 22621 为最低门槛。

### `sparseVhd=true`

默认值为 `false`。启用后，新创建的 WSL VHD 会自动使用 sparse 模式，便于宿主机回收未使用的虚拟磁盘空间。它不会自动转换或压缩已经存在的发行版 VHD；现有磁盘仍需使用 WSL 提供的单独管理命令处理。

这是实验性设置。应使用较新的 Microsoft Store 版 WSL；安装清单仅在 Windows build 22621 或更高版本生成它。

### `hostAddressLoopback=true`

默认值为 `false`，且只在 mirrored 网络模式下生效。启用后，Windows 和 WSL 可以通过分配给 Windows 宿主机的 IPv4 地址互访。本项目保留它，主要用于 Tailscale 地址和 LAN IPv4 地址；仅使用 `127.0.0.1`/`localhost` 时不需要此项。该功能目前仅支持 IPv4。

这是实验性设置。应使用较新的 Microsoft Store 版 WSL；安装清单仅在 Windows build 22621 或更高版本生成它。

## 部署与生效

仓库安装流水线会根据 Windows build 过滤设置，并将生成内容写入 `%UserProfile%\.wslconfig`。内容变化时会先在同目录创建带可读时间戳的 `.bak` 备份。

修改配置后，保存所有 WSL 工作并执行：

```powershell
wsl --shutdown
```

该命令会终止所有 WSL 发行版，也可能暂时中断 Docker Desktop 的 WSL 后端。下一次启动发行版时加载新配置。

## 官方参考

- [WSL 的高级设置配置](https://learn.microsoft.com/windows/wsl/wsl-config)
- [使用 WSL 访问网络应用程序](https://learn.microsoft.com/windows/wsl/networking)
