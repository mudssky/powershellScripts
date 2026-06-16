# Hammerspoon 配置优化设计

## Architecture

本次改造把 `macos/hammerspoon` 拆成三层：

- `init/init.lua`：固定启动器，只负责加载配置、显式加载功能脚本、注册 reload 快捷键和文件监听。
- `config.lua` + `config.local.lua`：仓库默认配置与本机覆盖。默认配置提交到仓库，本机覆盖部署到 `~/.hammerspoon/config.local.lua` 并由 `.gitignore` 忽略。
- `win.lua`：功能脚本。只读取 `HammerspoonConfig`，按功能组注册快捷键，不再要求用户直接修改主逻辑。

## Data Flow

```text
仓库 config.lua
  -> 部署到 ~/.hammerspoon/config.lua
  -> init.lua 加载默认配置
  -> 可选加载 ~/.hammerspoon/config.local.lua 覆盖
  -> win.lua 读取 HammerspoonConfig
  -> 按 enabledGroups 注册快捷键
```

配置合并只做浅层与一层表合并，避免 Lua 配置逻辑复杂化。`config.local.lua` 返回表时覆盖默认值；为了兼容旧配置，也继续读取 `_G.modifierSwapped` 和 `HAMMERSPOON_MODIFIER_SWAP`，但 README 不再推荐环境变量作为主入口。

## Default Behavior

默认启用低冲突核心组：

- `window`：窗口左半屏、右半屏、最大化、最小化。
- `launcher`：锁屏、Finder、Spotlight、System Settings。
- `reload`：`Cmd+Alt+Ctrl+R` 重新加载配置。

默认核心组使用 `Cmd+Alt+Ctrl` 组合，避免覆盖裸 `Cmd+Left`、`Cmd+R`、`Cmd+I` 等 macOS 常用快捷键。

默认关闭：

- `altTab`
- `text`
- `browser`
- `finderActions`
- `spaces`
- `apps`
- `screenshot`
- `volume`

`Alt+Tab` 作为独立组，不并入核心组。

## Compatibility

- `System Settings` 优先，`System Preferences` 保留为旧系统 fallback。
- `launchOrFocusApp` 提前定义，避免 Lua local 闭包引用顺序问题。
- `modifierSwap` 默认关闭，减少“文档写 Win 实际按 Ctrl”的认知错位；旧环境变量和 `_G.modifierSwapped` 仍可覆盖。
- `init.lua` 改为显式加载 `scripts/win.lua`，避免扫描顺序不稳定。

## Deployment

`load_scripts.zsh` 支持：

- `--dry-run`：只展示动作。
- `--no-launch`：部署后不启动或重启 Hammerspoon。
- `--install`：未检测到 Hammerspoon 时执行 `brew install --cask hammerspoon`。

部署脚本负责：

- 使用 `open -Ra Hammerspoon` 和常见路径检测安装。
- 备份将被覆盖的 `init.lua`、默认 `config.lua` 和托管脚本。
- 保留已有 `config.local.lua`，缺失时从 `config.local.example.lua` 生成。
- 使用 manifest 记录托管文件，只清理上一轮托管但本轮不再存在的脚本，避免误删用户自定义文件。

## Validation

- Lua 语法：优先用可用的 `lua`/`luac`，若本机没有则用文本与 shell dry-run 校验。
- 部署脚本：运行 `zsh -n macos/hammerspoon/load_scripts.zsh`，并运行 `zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch`。
- 安装清单：确认 Hammerspoon 同时有 `supportOs: ["macOS"]` 和 `tag: ["macbook"]`。
- 仓库质量：执行根目录 `pnpm qa`。
