# Hammerspoon 合盖休眠保护实施计划

## Checklist

- [x] A1. 确认蓝牙处理策略，并把结论写回 `prd.md` 与 `design.md`。
- [x] A2. 更新 `config.lua` 和 `config.local.example.lua`，新增 `plugins["power-lid-sleep"]` 配置；按用户最新要求仓库默认启用合盖休眠保护和蓝牙守卫。
- [x] A3. 将 `win.lua` 迁移为 `plugins/win-hotkeys/plugin.lua`，保持现有快捷键行为和兼容配置语义。
- [x] A4. 更新 `init/init.lua`，增加插件加载器，并按显式插件清单启动 `win-hotkeys` 与 `power-lid-sleep`。
- [x] A5. 新增 `plugins/power-lid-sleep/plugin.lua` 和插件私有模块，实现设备门禁、合盖、电池、RustDesk 空闲退出和蓝牙策略入口。
- [x] A6. 更新 `profile/installer/apps-config.json`，新增 `blueutil` macbook 安装项。
- [x] A7. 更新 `load_scripts.zsh`，支持托管插件目录递归复制、备份、manifest 写入和旧托管文件清理。
- [x] A8. 更新 README，说明插件目录结构、配置方式、蓝牙依赖、风险边界和 dry-run 部署验证。
- [x] A9. 更新 `macos/06verifyInstall.zsh` 的 hammerspoon 检查项，验证插件化部署结果。
- [x] A10. 执行验证命令，修复发现的问题。

## Validation Commands

```zsh
zsh -n macos/hammerspoon/load_scripts.zsh
zsh -n macos/05deployHammerspoon.sh
zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch
pnpm qa
```

如果修改 `macos/06verifyInstall.zsh`：

```zsh
pnpm test:pwsh:all
```

## Validation Results

- `zsh -n macos/hammerspoon/load_scripts.zsh && zsh -n macos/05deployHammerspoon.sh && zsh -n macos/06verifyInstall.zsh`：通过。
- `npx --yes luaparse ...` 解析 `init.lua`、`win-hotkeys` 和 `power-lid-sleep` 所有 Lua 文件：通过。
- `zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch --install`：通过；会复制 5 个插件脚本、写入插件 manifest，并清理旧 `scripts/win.lua` 托管文件。
- `node` 解析 `profile/installer/apps-config.json` 并检查 `hammerspoon` / `blueutil` 的 macOS + macbook 配置：通过。
- `git diff --check`：通过。
- `pnpm qa`：通过，90 passed，6 not run。
- `pnpm test:pwsh:full:assertions`：通过，615 passed，4 skipped，24 not run。
- `pwsh -NoProfile -Command '$env:PWSH_TEST_MODE="full"; $env:PWSH_TEST_ENABLE_COVERAGE="true"; ...'`：通过，615 passed，4 skipped，24 not run，coverage 57.36% / 50%。
- `pnpm test:pwsh:all`：host 分支通过；Linux Docker 分支失败在容器构建/运行时未注册 `PSGallery`，导致 Pester 未安装、`Invoke-Pester` 不存在。该失败属于当前 Docker 测试环境/镜像依赖问题，非 Hammerspoon 变更直接失败。
- `brew install blueutil`：通过，安装 `blueutil 2.13.0`。
- `zsh macos/05deployHammerspoon.sh --install`：通过；已备份并部署 `~/.hammerspoon/init.lua`、`config.lua` 和 5 个插件脚本，保留本机 `config.local.lua`，并重启 Hammerspoon。
- `zsh macos/06verifyInstall.zsh --step apps`：通过，6 passed，0 warned，0 failed。
- `zsh macos/06verifyInstall.zsh --step hammerspoon`：通过，17 passed，0 warned，0 failed。
- `blueutil --power && blueutil --version`：通过，当前蓝牙电源状态为 `1`，版本 `2.13.0`。
- `pnpm qa`：启用并部署后复跑通过，90 passed，6 not run。

## Spec Update

- 新增 `.trellis/spec/infra/hammerspoon-plugins.md`，记录 Hammerspoon 插件目录、入口签名、配置合并、manifest 部署和验证契约。
- 更新 `.trellis/spec/infra/index.md`，把 Hammerspoon 插件契约纳入 infra spec 索引。

## Risky Files

- `macos/hammerspoon/init/init.lua`：加载失败会导致 Hammerspoon 配置整体不可用。
- `macos/hammerspoon/load_scripts.zsh`：会操作 `~/.hammerspoon`；验证时先用 dry-run，避免直接写入用户目录。
- `macos/hammerspoon/config.lua`：默认值必须保持保守，不能默认退出应用或修改蓝牙。
- `macos/hammerspoon/plugins/win-hotkeys/plugin.lua`：承载既有快捷键行为，迁移时必须避免默认快捷键范围漂移。
- `macos/06verifyInstall.zsh`：若新增检查过严，可能让安装验证在未启用 power 功能时误报失败。

## Follow-Up Before Start

- [x] 用户确认蓝牙策略。
- [x] 用户确认首版不加入外接显示器检测。
- [x] 用户确认把 `blueutil` 加入 macbook 安装集合。
- [x] 用户先确认合盖休眠保护可保持仓库默认关闭；后续明确要求“直接都启动”“合盖门禁也启动”，当前仓库默认配置已启用。
- [x] 用户确认 Mac mini 等非笔记本设备上不应生效。
- [x] 用户确认插件契约采用目录即插件和 `plugin.lua` 入口。
- [x] 用户确认现有 `win.lua` 也迁移为插件。
- [x] `prd.md`、`design.md`、`implement.md` 已更新到无阻塞问题。
- [ ] 用户明确批准进入实现阶段后，再执行 `python3 ./.trellis/scripts/task.py start 06-17-hammerspoon-lid-sleep-guard`。
