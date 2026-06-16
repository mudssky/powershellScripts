# macOS 安装验证设计

## Boundary

本任务只为 macOS 平台安装流水线补充可验证契约：

- 文档层：`macos/INSTALL.md` 说明每步的前置、执行和验证命令。
- 验证层：`macos/06verifyInstall.zsh` 汇总只读检查，给人和智能体稳定退出码。
- 现有安装层：`macos/01installHomeBrew.sh` 到 `macos/05deployHammerspoon.sh` 继续负责实际安装和部署。

验证脚本不替代安装脚本，也不自动调用安装脚本。

不把验证逻辑扩展进现有安装脚本的原因：

- 安装脚本有写入和安装副作用，验证脚本需要默认只读，方便智能体安全重复运行。
- 独立入口能验证“当前机器整体状态”，不要求用户刚刚执行过某个安装脚本。
- `--step` 已经能提供单步体验，文档中每一步仍可以写对应验证命令。

## Command Contract

建议入口：

```zsh
zsh macos/06verifyInstall.zsh
zsh macos/06verifyInstall.zsh --step brew
zsh macos/06verifyInstall.zsh --step pwsh
zsh macos/06verifyInstall.zsh --step shell
zsh macos/06verifyInstall.zsh --step apps
zsh macos/06verifyInstall.zsh --step hammerspoon
```

参数契约：

- `--step <name>`：只验证一个阶段。合法值首版固定为 `repo`、`brew`、`pwsh`、`shell`、`apps`、`hammerspoon`。
- `-h|--help`：输出帮助并返回 0。
- 未知参数或未知 step 返回 2。
- 检查失败返回 1。
- 所有检查通过返回 0。

## Step Checks

### repo

检查当前目录是否为仓库根目录：

- 存在 `macos/INSTALL.md`。
- 存在 `profile/installer/apps-config.json`。
- 存在 `.git` 或 `git rev-parse --show-toplevel` 能解析到当前仓库。

### brew

检查 Homebrew 是否可用：

- `command -v brew`。
- `brew --prefix` 可执行。

### pwsh

检查 PowerShell 是否可用：

- `command -v pwsh`。
- `pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'` 返回成功。

### shell

检查 shell 部署结果：

- `~/.zshrc` 存在。
- `~/.zshrc` 包含 modular loader，不要求 symlink 到仓库文件。
- `~/.bashrc.d` 存在。
- `~/.bashrc.d` 至少包含来自仓库 `shell/shared.d` 或 `shell/zsh.d` 的 symlink。

旧的 `macos/config/.zshrc` 只保留在 `macos/archive/config/.zshrc` 作为历史参考；当前安装路径不再替换整个 `~/.zshrc`。

### apps

首版检查关键代表项：

- `brew list --cask hammerspoon` 或 `open -Ra Hammerspoon` 能找到 Hammerspoon。
- `command -v starship` 检查 CLI 类应用代表项。
- 可选检查 `iterm2`、`keka`、`maccy` 等 GUI App，缺失时可先记 WARN，避免把个人可选应用变成硬失败。

后续可以从 `apps-config.json` 动态读取 `macOS + macbook + !skipInstall` 列表，但首版不强行验证全部 GUI App，避免刚装新机器时因个别可选工具失败阻塞主链路。

### hammerspoon

检查 Hammerspoon 配置部署结果：

- Hammerspoon App 可被 `open -Ra Hammerspoon` 找到，或存在常见安装路径。
- `~/.hammerspoon/init.lua` 存在。
- `~/.hammerspoon/config.lua` 存在。
- `~/.hammerspoon/config.local.lua` 存在。
- `~/.hammerspoon/scripts/win.lua` 存在。
- `~/.hammerspoon/.powershellscripts-hammerspoon.manifest` 存在，且包含 `init.lua`、`config.lua`、`scripts/win.lua`。

不检查辅助功能权限和快捷键触发结果，因为这需要用户授权和交互环境。

## Output Model

输出保持简单、可扫描：

```text
[PASS] brew: brew command is available
[WARN] apps: maccy is not installed
[FAIL] hammerspoon: ~/.hammerspoon/init.lua not found
```

脚本结尾输出汇总：

```text
Summary: 8 passed, 1 warned, 1 failed
```

WARN 不影响退出码；FAIL 影响退出码。

## Trade-Offs

- 单一 `06verifyInstall.zsh` 比每步一个独立脚本更容易维护，也方便智能体只记一个入口。
- `--step` 保留了单步验证体验，文档仍可把每一步写成独立验证命令。
- 首版不动态解析全部应用清单，可以减少 PowerShell/JSON 解析依赖和误报；代价是不能百分百证明所有 `macbook` 应用都安装成功。
- 不提供 `--fix` 可以保持验证命令无副作用；代价是失败后需要再运行对应安装脚本。

## Compatibility

- 脚本使用 zsh，匹配 `macos/*.sh` 的现有平台脚本风格。
- 验证命令以仓库根目录为执行位置，和 `macos/INSTALL.md` 的命令口径保持一致。
- 不依赖网络，不修改本机状态。
