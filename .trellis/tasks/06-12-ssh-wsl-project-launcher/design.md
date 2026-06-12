# Design: SSH/WSL 项目启动脚本

## Architecture

本功能分成四个边界：

- `psutils/src/config`：新增 SSH config 读取器，负责把 OpenSSH client config 的 `Host` block 解析成结构化对象。
- `psutils/modules/config.psm1`：导出 SSH config 读取函数，保持公共配置读取能力的唯一入口。
- `scripts/pwsh/devops/project-launcher/`：新增启动器脚本目录，负责读取配置来源、合并启动 catalog、交互选择、生成执行计划与调用外部命令。
- `tests` / `psutils/tests`：分别覆盖公共读取器与启动器业务逻辑。

## Reuse Constraints

- 交互选择必须复用 `psutils/modules/selection.psm1` 的 `Select-InteractiveItem`。启动器只提供启动项展示文案和取消后的控制流，不直接调用 `fzf`，也不复制文本编号降级逻辑。
- 通用配置来源读取必须复用 `psutils/modules/config.psm1` 的 `Resolve-ConfigSources`。启动器只声明默认值、JSON 文件和 CLI 参数的来源顺序，不用 `Get-Content | ConvertFrom-Json` 重新实现通用 JSON 配置读取。
- SSH config 是当前 `psutils/src/config` 尚未覆盖的格式；新增读取器应放入共享 config 模块，而不是只写在启动器脚本内部。
- `xx.md` 是一次性临时草稿，不作为实现输入、测试 fixture 或用户文档。草稿中的有效内容已转写到本任务的 PRD/design/implement。

## Data Sources

### SSH Config

默认读取用户主目录下的 `.ssh/config`，也允许 CLI 指定测试或临时路径。读取器只解析当前启动器需要的 Host block 信息：

- `Host`
- `HostName`
- `User`
- `Port`
- `RemoteCommand`
- `RequestTTY`

解析结果保留为普通 SSH 启动项。启动器执行普通 SSH 项时只调用 `ssh <Host>`，不重新拼接 `HostName`、`User`、`Port`，避免和 OpenSSH 自身解析逻辑漂移。

SSH config 解析封装必须由 `psutils/modules/config.psm1` 导出，启动器通过该公共函数读取，不在启动器内部维护第二份 parser。

### JSON Increment

自定义 JSON 是增量 catalog，不覆盖 SSH config 已有 Host 的核心连接字段。建议 schema：

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
      "name": "wsl-custom-command",
      "type": "wsl",
      "distro": "Debian",
      "command": "cd ~/work/demo && exec zellij attach -c demo"
    },
    {
      "name": "proj-srm-trellis",
      "displayName": "SRM Trellis",
      "tags": ["remote", "work"]
    }
  ]
}
```

`type` 缺省时按 metadata patch 处理，只能补充显示字段。`type = "wsl"` 时创建 WSL 启动项。若 JSON entry 与 SSH Host 同名，只允许合并显示元数据，例如 `displayName`、`tags`、`order`、`hidden`；不得覆盖 `Host`、`HostName`、`User`、`Port`、`RemoteCommand`。

## Launch Item Model

启动器内部统一使用启动项对象：

- `Name`：唯一入口名。
- `Type`：`ssh` 或 `wsl`。
- `DisplayName`：可选展示名。
- `Target`：目标摘要，例如 `user@host:port` 或 `WSL:Ubuntu-24.04`。
- `CommandSummary`：`RemoteCommand` 或 WSL shell command 的摘要。
- `Source`：`ssh-config`、`json` 或 `ssh-config+json`。
- `Raw`：保留来源字段供测试和 dry-run 使用。

## Filtering

SSH config 过滤规则：

- `Host` 行包含多个 pattern 时不作为普通启动项。
- Host 名包含 `*`、`?`、`!` 或空白时过滤。
- 缺少 Host 名的 block 过滤。

平台过滤规则：

- Windows 平台展示 `ssh` 与 `wsl`。
- 非 Windows 平台只展示 `ssh`，过滤 `wsl`，避免用户选择不可执行入口。

## Command Planning

启动器先生成执行计划，再执行外部命令。这样 dry-run、测试和真实调用共享同一条业务路径。

SSH 执行计划：

```text
ssh -tt <Name>
```

如果 SSH config 明确声明 `RequestTTY no`，执行计划退回 `ssh <Name>`，尊重用户配置。

WSL 执行计划：

```text
wsl.exe -d <Distro> -- bash -lc <Command>
```

WSL 命令解析：

- entry 存在 `command` 时直接使用该命令。
- entry 不存在 `command` 时，要求存在 `workDir` 与 `session`，生成 `cd <workDir> && exec zellij attach -c <session>`。
- `distro` 优先使用 entry 级配置，缺省时读取 `defaults.wsl.distro`。
- 缺少最终 distro 或缺少可生成命令的字段时抛出带 entry 名称的配置错误。

真实执行策略：

- dry-run 只输出执行计划，不启动外部进程。
- Windows 下默认把 SSH/WSL 交互会话放到 Windows Terminal 新标签页；新标签页内通过 `pwsh -NoExit -File <temp-script>` 按参数数组调用真实命令，避免 `wt.exe` 把 `;` 当成新标签页命令分隔符，也避免 WSL command 被 `cmd.exe` 二次解释。没有 `wt.exe` 时退到独立 PowerShell 控制台。
- 用户显式传入 `-Inline` 时，才在当前 PowerShell 进程内直接执行 SSH/WSL。该模式用于用户确实想让会话占用当前终端的场景。

## Compatibility

- 不写入真实 `~/.ssh/config`。
- 不尝试展开 OpenSSH `Include`、`Match`、条件块和完整继承语义；第一版只做启动菜单所需的 block 读取。真实连接仍交给 `ssh <Host>`。
- 自定义 JSON 通过现有 `Resolve-ConfigSources` 读取，让 CLI 覆盖与默认值符合项目配置规范。
- 交互选择复用 `Select-InteractiveItem`，缺失 fzf 时自动文本降级。

## Validation

- `psutils/tests/config.Tests.ps1` 或新建 focused 测试覆盖 SSH config 读取器。
- 新增启动器 Pester 测试覆盖 catalog 合并、JSON 增量、WSL 默认 distro、command 优先级、非 Windows 过滤、dry-run 执行计划和交互取消。
- 代码修改后执行 `pnpm qa`；提交前按项目规则执行 `pnpm test:pwsh:all`，Docker 不可用时退到 `pnpm test:pwsh:full`。
