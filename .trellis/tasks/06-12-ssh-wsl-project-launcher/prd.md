# SSH/WSL 项目启动脚本

## Goal

开发一个 PowerShell 项目启动器，从 SSH config 与用户自定义 JSON 配置中汇总项目入口，通过既有交互选择能力让用户选择目标，并按入口类型启动远程 SSH 会话或本机 WSL 项目环境。

目标价值是把已有 `~/.ssh/config` 中的 `Host` / `RemoteCommand` 项目入口变成可搜索菜单，同时为不适合写入 SSH config 的 WSL 项目入口提供独立配置来源。

## Confirmed Facts

- 用户临时草稿中已有方案要点已沉淀到本 PRD：读取 `~/.ssh/config`，解析 `Host`、`HostName`、`User`、`Port`、`RemoteCommand`；普通远程入口执行 `ssh <Host>`；WSL 入口执行 `wsl.exe -d <Distro> -- bash -lc '<command>'`。
- `xx.md` 是临时草稿，后续会删除；实现、文档和测试不得依赖或更新该文件。
- `psutils/modules/selection.psm1` 已提供 `Select-InteractiveItem`，会优先使用 `fzf`，缺失时自动降级为文本编号选择。
- `psutils/modules/config.psm1` 与 `psutils/src/config` 已提供 JSON/env/psd1/frontmatter/CLI 参数合并能力，新脚本应复用 `Resolve-ConfigSources`，避免重新实现 JSON 读取与覆盖逻辑。
- `psutils/src/config` 当前还没有 SSH config 读取封装；如果需要公共复用，应在 `psutils/src/config` 增加读取器并通过 `psutils/modules/config.psm1`、`psutils/psutils.psd1` 导出。
- `scripts/pwsh/devops/Invoke-Benchmark.ps1` 已展示“缺少显式名称时用 `Select-InteractiveItem` 选择候选项”的本地模式，可作为启动器交互层参考。
- 项目规则要求修改 `scripts/pwsh/**` 或 `psutils/**` 后执行 `pnpm qa`；涉及 pwsh 内容时提交前还需执行 `pnpm test:pwsh:all`，Docker 不可用时至少执行 `pnpm test:pwsh:full` 并说明 Linux 覆盖依赖。

## Requirements

- 新增一个 `scripts/pwsh` 下的项目启动脚本，能够在未显式指定项目时展示可搜索选择列表。
- 启动器必须优先复用项目内既有 fzf/交互选择封装 `Select-InteractiveItem` 完成交互选择，不单独维护 fzf 调用逻辑。
- 启动器必须优先复用项目内既有配置读取封装 `Resolve-ConfigSources` 读取自定义 JSON 配置与 CLI 覆盖参数，不单独维护通用 JSON 配置合并逻辑。
- 启动器必须能够读取 SSH config 中的普通 `Host` block，并生成 `ssh <Host>` 启动项。
- 必须在 `psutils/src/config` 增加可复用 SSH config 解析封装，用于读取单文件 OpenSSH client config 的 `Host` block。
- SSH config 解析应过滤不适合作为交互入口的 `Host` pattern，例如包含空白、通配符或多 host pattern 的条目。
- 启动器必须支持 WSL 类型启动项；WSL 项在 Windows 环境执行 `wsl.exe -d <Distro> -- bash -lc '<command>'`。
- 自定义 JSON 必须支持全局默认 WSL 发行版配置，单个 WSL 启动项可按需覆盖发行版。
- WSL 启动项必须允许显式 `command` 字段；配置了 `command` 时按该命令执行，没有 `command` 时可由 `workDir` 与 `session` 拼装默认 zellij 启动命令。
- 非 Windows 环境必须过滤 WSL 类型启动项，避免展示当前平台无法执行的入口。
- 启动项展示信息应至少包含入口名称、类型、目标位置和启动命令摘要，便于在 fzf 或文本降级模式下判断。
- 必须支持用户指定自定义 JSON 配置文件；配置文件只作为增量来源，用于新增非 SSH config 启动项或补充显示元数据，不覆盖 SSH config 中已有 Host 的核心连接配置。
- 必须提供非交互路径：用户显式传入入口名称时可直接启动，便于脚本化和测试。
- 必须提供 dry-run 或等价预览能力，用于输出将要执行的命令而不真正启动 SSH/WSL。
- 不修改用户真实 `~/.ssh/config`，本轮只读取配置并启动。
- 不维护 WSL 内 sshd，不把 WSL 项目入口伪装成必须通过 SSH 连接的服务。

## Acceptance Criteria

- [ ] 可从测试 fixture SSH config 中解析普通 Host 启动项，且包含 Host、HostName、User、Port、RemoteCommand 等字段。
- [ ] SSH config 解析能力通过 `psutils/modules/config.psm1` 和 `psutils/psutils.psd1` 对外导出，可被启动器复用。
- [ ] 带通配符、空白分隔多个 pattern 或不适合直接 `ssh <Host>` 的 Host block 不会出现在启动候选项中。
- [ ] 自定义 JSON 配置可提供 WSL 启动项，并能参与启动项列表。
- [ ] 自定义 JSON 与 SSH config 出现同名入口时，不覆盖 SSH config 的 Host、HostName、User、Port、RemoteCommand 等核心连接字段。
- [ ] WSL 启动项缺少 entry 级 `distro` 时，可使用 JSON 全局默认 WSL 发行版。
- [ ] WSL 启动项配置 `command` 时，执行计划使用该命令；未配置 `command` 时，可由 `workDir` 与 `session` 生成 zellij attach 命令。
- [ ] 在 Windows 平台，WSL 启动项会生成 `wsl.exe -d <Distro> -- bash -lc <command>` 执行计划。
- [ ] 在非 Windows 平台，WSL 启动项会被过滤，普通 SSH 启动项仍可用。
- [ ] 未显式指定入口名时，脚本通过 `Select-InteractiveItem` 选择启动项；取消选择时不执行任何启动命令并正常退出。
- [ ] 启动器代码没有直接调用 `fzf` 或复制 `Select-InteractiveItem` 已覆盖的文本降级逻辑。
- [ ] 启动器代码没有直接用 `Get-Content | ConvertFrom-Json` 实现通用配置来源读取；JSON 配置进入 `Resolve-ConfigSources` 的来源合并流程。
- [ ] 显式指定入口名时，脚本跳过交互选择并解析对应启动项。
- [ ] dry-run 模式输出将执行的 SSH 或 WSL 命令，且不启动外部会话。
- [ ] 相关 `psutils` 读取器、启动项解析、平台过滤和命令计划有 focused Pester 覆盖。
- [ ] 修改完成后按项目规则执行 `pnpm qa`；提交前执行 `pnpm test:pwsh:all`，如 Docker 不可用则执行 `pnpm test:pwsh:full` 并说明。

## Out of Scope

- 本轮不自动生成、编辑或迁移用户真实 `~/.ssh/config`。
- 本轮不写入或维护 `xx.md`；它只作为已吸收的临时草稿存在，可在任务完成前后删除。
- 本轮不配置 WSL 发行版、安装 zellij、安装 OpenSSH 或管理远程服务器状态。
- 本轮不替换 VS Code Remote SSH 配置，也不处理 SSH 断连诊断。
- 本轮不实现 GUI、Windows Terminal profile 管理或多标签窗口编排。

## Decisions

- 自定义 JSON 作为增量配置，不覆盖 SSH config 已有配置。
- WSL 启动项允许 `command` 字段；JSON 支持 `defaults.wsl.distro` 作为默认发行版，entry 级 `distro` 可覆盖默认值。
- JSON schema 固化为 `defaults.wsl.distro` + `entries[]`，避免把 WSL 专属默认值放到顶层全局字段。

## Open Questions

- 无阻塞规划的问题。

## Notes

- 这是复杂任务，进入实现前需要补充 `design.md` 与 `implement.md`。
