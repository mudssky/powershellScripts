# WSL2 配置模板

## 目录

- [模板文件](#模板文件)
- [使用方法](#使用方法)
- [选择建议](#选择建议)

## 模板文件

这些模板是 skill 内置资产，安装到全局后仍可直接复制，不依赖外部仓库文件。

| 文件 | 目标路径 | 适用场景 |
|---|---|---|
| `assets/wsl2/lightweight.wslconfig` | `%UserProfile%\.wslconfig` | 16GB 内存以内机器、少量容器、偶尔运行数据库 |
| `assets/wsl2/balanced.wslconfig` | `%UserProfile%\.wslconfig` | 32GB 左右内存机器、日常 compose 栈、多个开发数据库 |
| `assets/wsl2/heavy.wslconfig` | `%UserProfile%\.wslconfig` | 64GB+ 内存机器、多套 compose 或较重构建任务 |
| `assets/wsl2/docker-engine.wsl.conf` | WSL 发行版内 `/etc/wsl.conf` | 在 WSL2 发行版内直接运行 Docker Engine |
| `assets/wsl2/minimal-systemd.wsl.conf` | WSL 发行版内 `/etc/wsl.conf` | 只启用 systemd，不改变 Windows 盘挂载语义 |

## 使用方法

`.wslconfig` 是 Windows 用户级全局配置。复制前先备份：

```powershell
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
Copy-Item "$env:USERPROFILE\.wslconfig" "$env:USERPROFILE\.wslconfig.$stamp.bak" -ErrorAction SilentlyContinue
```

从已安装 skill 目录复制。Claude Code 常见路径是 `~/.claude/skills/docker-management`，Codex universal skill 常见路径是 `~/.agents/skills/docker-management`。

```powershell
$skill = "$env:USERPROFILE\.agents\skills\docker-management"
Copy-Item "$skill\assets\wsl2\balanced.wslconfig" "$env:USERPROFILE\.wslconfig" -Force
wsl --shutdown
```

`/etc/wsl.conf` 是单个 WSL 发行版内配置。复制到发行版内后，也要在 Windows 侧执行 `wsl --shutdown`。

```bash
sudo cp /path/to/docker-engine.wsl.conf /etc/wsl.conf
```

如果 agent 不知道 skill 的安装路径，先定位当前加载的 skill 根目录，或让用户提供安装目录；不要引用项目仓库路径。

## 选择建议

- 只跑一两个服务：`lightweight.wslconfig`。
- 本机常驻 PostgreSQL、Redis、MongoDB、MinIO 等开发依赖：`balanced.wslconfig`。
- 同时跑多套 compose 栈或大型构建：`heavy.wslconfig`，并配合容器级 `--memory` / `--cpus` 限制。
- 不确定时从 `balanced.wslconfig` 降低内存值开始；比起一次给太多资源，逐步上调更容易定位性能问题。
- 在 WSL2 内直接运行 Docker Engine：`docker-engine.wsl.conf`。
- 只需要 systemd：`minimal-systemd.wsl.conf`。
