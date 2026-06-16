# Hammerspoon 配置优化实施计划

## Checklist

- [x] A1. 新增 `macos/hammerspoon/config.lua` 和 `config.local.example.lua`。
- [x] A2. 重写 `init/init.lua`：加载默认配置、本机覆盖、显式加载脚本、注册 reload 与 watcher。
- [x] A3. 重构 `win.lua`：提前应用启动辅助函数，按功能组注册快捷键，默认精简核心组。
- [x] A4. 新增 `.gitignore`，避免本机 Hammerspoon 覆盖配置和备份进入仓库。
- [x] B1. 重写 `load_scripts.zsh`：参数、安装检测、可选安装、备份、manifest 同步、本机配置保留。
- [x] B2. 更新 `macos/05deployHammerspoon.sh`，透传部署参数。
- [x] C1. 更新 README，说明默认核心组、可选组、本机 local 覆盖和安装方式。
- [x] C2. 更新 `profile/installer/apps-config.json`，给 Hammerspoon 增加 `macbook` tag。
- [x] D1. 校验 shell 语法与 dry-run。
- [x] D2. 校验 Lua 语法或说明本机缺少 Lua CLI。
- [x] D3. 执行 `pnpm qa`。

## Validation Results

- `zsh -n macos/hammerspoon/load_scripts.zsh && zsh -n macos/05deployHammerspoon.sh`：通过。
- `zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch --install`：通过，仅模拟部署和安装，不写入 `~/.hammerspoon`。
- `node` 校验 `profile/installer/apps-config.json`：通过，Hammerspoon 同时包含 `supportOs: ["macOS"]` 与 `tag: ["macbook"]`。
- `node` 校验默认 Hammerspoon 配置：通过，核心组默认开启，可选组默认关闭，核心快捷键使用 `Cmd+Alt+Ctrl` 低冲突组合。
- `git diff --check`：通过。
- `pnpm qa`：通过，Pester QA 90 passed，6 not run；Linux-only Bash/FNOS/systemd QA 在 Darwin 上按项目脚本跳过。
- 本机缺少 `lua` / `luac` CLI，未执行 Lua CLI 语法检查；已用 Hammerspoon dry-run 复制路径、文本检查和默认配置检查补充验证。

## Risky Files

- `macos/hammerspoon/win.lua`：快捷键行为面广，默认组必须严格收窄。
- `macos/hammerspoon/load_scripts.zsh`：会操作 `~/.hammerspoon`，验证时只跑 dry-run，不实际部署。
- `profile/installer/apps-config.json`：必须保持 JSON 有效，并与 `macos/04installApps.ps1` 的 `macbook` 筛选一致。

## Rollback

- 若 Hammerspoon Lua 行为异常，可回滚 `macos/hammerspoon/*.lua` 和 `init/init.lua`。
- 若部署脚本风险过高，可保留配置改造，仅回滚 `load_scripts.zsh` 参数与 manifest 同步逻辑。
- 若安装清单改动引起额外安装范围，回滚 Hammerspoon 的 `macbook` tag。
