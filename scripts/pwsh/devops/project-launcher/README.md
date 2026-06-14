# Project Launcher

从 SSH config 与 JSON 增量配置汇总项目入口，通过 fzf 或文本编号选择后启动 SSH / WSL 项目会话。

安装 bin shim：

```powershell
pwsh -NoProfile -File ./Manage-BinScripts.ps1 -Action sync -Force
```

常用命令：

```powershell
./bin/Invoke-ProjectLauncher.ps1
./bin/Invoke-ProjectLauncher.ps1 proj-srm-trellis
./bin/Invoke-ProjectLauncher.ps1 wsl-srm-trellis
./bin/Invoke-ProjectLauncher.ps1 wsl-srm-trellis -ConfigPath ./project-launcher.json
./bin/Invoke-ProjectLauncher.ps1 wsl-srm-trellis -ConfigPath ./project-launcher.json -DryRun
./bin/Invoke-ProjectLauncher.ps1 proj-srm-trellis -Inline
```

## SSH 来源

默认读取当前用户的 `~/.ssh/config`。普通 Host 会生成 SSH 启动项，执行计划只包含：

```powershell
ssh -tt <Host>
```

脚本会解析并展示 `HostName`、`User`、`Port`、`RemoteCommand` 等摘要，但不会重新拼接 SSH 连接参数，也不会修改真实 SSH config。默认会为 SSH 会话追加 `-tt`，让远端 shell 拿到交互式 TTY；如果 SSH config 明确写了 `RequestTTY no`，则不会强制追加。

## JSON 增量配置

JSON 只做增量：新增 WSL 启动项，或为同名 SSH Host 补展示元数据，不覆盖 SSH 的核心连接字段。

默认会自动读取当前目录存在的 `project-launcher.json` 与 `project-launcher.local.json`。显式传入 `-ConfigPath ./foo.json` 时，也会在同目录存在 `foo.local.json` 时自动追加读取。`*.local.json` 已在仓库 `.gitignore` 中忽略，适合放本机私有项目入口。

```json
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-24.04"
    }
  },
  "entries": [
    {
      "name": "wsl-srm-trellis",
      "type": "wsl",
      "workDir": "~/projects/work/hubs/srm-trellis",
      "session": "srm-trellis"
    },
    {
      "name": "wsl-demo",
      "type": "wsl",
      "distro": "Debian",
      "command": "cd ~/projects/demo && exec zellij attach -c demo"
    },
    {
      "name": "proj-srm-trellis",
      "displayName": "SRM Trellis",
      "tags": ["remote", "work"]
    }
  ]
}
```

WSL 启动项优先使用 entry 级 `distro`，缺省时使用 `defaults.wsl.distro`。配置了 `command` 时直接执行该命令；未配置时用 `workDir` 与 `session` 生成：

```text
cd <workDir> && exec zellij attach -c <session>
```

非 Windows 平台会过滤 WSL 启动项，只保留 SSH 项。

真实执行前会打印 `启动: <command>`。Windows 下默认打开 Windows Terminal 新标签页承载 SSH/WSL 会话，当前 PowerShell 会立即返回，避免 fzf 选择后的 shell 被远端交互会话占住。需要在当前终端内执行时加 `-Inline`。
