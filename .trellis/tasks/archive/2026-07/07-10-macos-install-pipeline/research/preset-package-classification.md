# macOS 预设软件分类候选

## 分类原则

- 预设表达使用场景，不再让 `macbook` 同时代表 CLI、字体、GUI 和平台依赖。
- `apps-config.json` 继续作为软件真源，通过明确 preset/category 元数据筛选，不复制第二份安装清单。
- 已有 `skipInstall: true` 继续优先于预设，除非后续单独审阅并解除。
- PowerShell、Homebrew、chsrc、Node/pnpm 等 bootstrap/runtime 依赖由对应编号步骤负责，不因它们也出现在应用清单而重复安装。

## Core CLI 推荐集合

以下工具已由 Profile、shell、仓库安装或高频脚本直接消费，建议进入默认 Core：

| 工具 | 证据与职责 |
|---|---|
| `fnm` | Profile 初始化显式支持 fnm，用于获得 Node；Stage 7 的 Node/pnpm 工具构建依赖 Node 环境 |
| `jq` | `shell/shared.d/proxy.sh`、AI profile shell 等脚本直接处理 JSON |
| `fd` | 根 `package.json` 的 notebook 清理命令直接调用，亦为常用文件搜索入口 |
| `eza` | shell aliases 与 PowerShell 用户别名直接提供 `ll`、`tree` |
| `ripgrep` | 仓库搜索与脚本开发基础工具，三个目标平台均已有对应包 |
| `fzf` | Bash/Zsh history 和 PowerShell 延迟键绑定直接支持 |
| `zoxide` | shell prompt 与 PowerShell Profile 直接初始化 |
| `starship` | Bash/Zsh 与 PowerShell Profile 直接初始化提示符 |
| `bat` | 跨平台终端查看工具，当前 macbook 清单已包含 |
| `uv` | `Manage-BinScripts.ps1` 生成的 Python shim 直接依赖，根 QA 也通过 `uvx` 运行 Python 工具 |

该集合不包含 GUI、字体或只由 Full 平台自动化消费的工具。

用户已确认上述 10 个工具作为首期 Core CLI。

## Terminal Extras 候选

这些工具仍是有效 CLI，但不是 Core 执行链硬依赖，建议保留在主清单并通过单步、显式 include group 或后续扩展预设安装：

- 当前带 `macbook` 标签：`pyenv`、`duf`、`dua-cli`、`lazygit`、`xh`、`neovim`、`zellij`、`herdr`。
- 当前未标 `macbook`：`xz`、`yazi`、`sevenzip`、`poppler`、`resvg`、`imagemagick`、`ast-grep`、`just`、`yq`、`bottom`、`llmfit`。
- npm/bun AI CLI：Gemini、Qwen、Claude Code、Codex、OpenSpec 等存在重复包管理器声明。用户已确认统一增加 `ai-cli`、`cli` 标签，但不增加 `core/full`，只在显式选择时安装；唯一包管理器由后续独立范围决定。

`pyenv` 与 `uv`、fnm 与 Node 安装、npm 与 bun 的职责有重叠，不能仅因当前已有条目就全部进入默认预设。

## Fonts

`06 fonts` 独立安装并验证：

- `font-jetbrains-mono-nerd-font`
- `font-fira-code-nerd-font`
- `font-symbols-only-nerd-font`

字体不再由 GUI/CLI 应用步骤隐式安装。

## Full GUI 与平台集成

当前带 `macbook` 标签且属于 GUI/平台集成的候选：

- 容器与桌面：`orbstack`
- 终端与工具：`iterm2`、`keka`、`maccy`、`hiddenbar`、`stats`
- 自动化：`mos`、`hammerspoon`、`blueutil`
- 编辑器 GUI：`neovide`

其中 `blueutil` 虽是 CLI，但由 macOS 蓝牙 helper 和 Hammerspoon 场景消费，建议跟随 Full 平台集成，而不是进入跨平台 Core。

当前未带 `macbook` 的 `dockdoor`、Docker Desktop 等 GUI 不自动纳入 Full，除非后续显式分类。`jordanbaird-ice`、`go`、`ffmpeg`、`dust` 等已有 `skipInstall: true` 的条目保持跳过。

## 已选配置位置与标签约定

唯一配置位置为 `profile/installer/apps-config.json`。仓库当前只有 macOS、Linux 和 `Install-PackageManagerApps` 示例按 `tag` 过滤，没有独立 schema 或其他消费者要求新增字段。因此沿用现有 `tag` 数组，并约定以下标签维度：

- 场景：`macbook`、`linuxserver`，保留现有设备/环境筛选语义。
- 预设：`core`、`full`。Full 选择 `core` 或 `full`；无这两个标签的条目默认不由预设安装。
- 类别：`cli`、`font`、`gui`、`platform`，用于路由编号步骤和验证方式。
- 可选组：`terminal-extras`、`ai-cli`，用于整组显式安装。

`skipInstall: true` 的优先级最高。所有新增标签使用小写 kebab-case。不得另建一份与 `apps-config.json` 平行的软件列表。

示例：

```json
{
  "name": "ripgrep",
  "cliName": "rg",
  "command": "brew install ripgrep",
  "supportOs": ["linux", "macOS"],
  "tag": ["linuxserver", "macbook", "core", "cli"]
}
```

调用关系：

- `05installCoreCli.ps1` 选择同时包含 `core` 与 `cli` 的条目。
- `06installFonts.ps1` 选择同时包含 `core` 与 `font` 的条目。
- `08` Full 应用步骤选择同时包含 `full` 与 `gui`/`platform` 的条目。
- 根 `install.ps1` 只选择步骤，不保存包名。
- `99verifyInstall.zsh` 或其 PowerShell helper 从同一配置读取 `cliName` 和类别标签，避免维护第二份验证列表。

配置校验应确保：同一条目不能同时标记 `core` 与 `full`；进入预设的条目必须且只能包含一个类别标签；未知保留标签或拼写错误应在 QA 中报错，而不是运行时静默漏装。
