# Design — WSL 内调用 browser-debug 创建 Windows 快捷方式与启动

## 架构与边界

```
WSL 交互式 shell (bash/zsh)
  └─ shell/shared.d/browser-debug.sh  → browser-debug() 函数
       └─ Windows pwsh 7 (绝对路径探测)
            └─ -NoProfile -ExecutionPolicy Bypass -File \\wsl.localhost\...\bin\browser-debug.ps1 "$@"
                 └─ scripts/pwsh/devops/browser-debug/main.ps1（Windows 进程内执行）
                      ├─ registry: D:\browser-debug-profiles\registry.json
                      ├─ .lnk 快捷方式: WScript.Shell COM（Windows 桌面）
                      └─ 浏览器: Windows 本地 chrome.exe / msedge.exe
```

AI agent 会话不走交互式 shell 初始化，直接使用 repo-ops reference 记录的等价直调命令。

## 关键设计决策

### D1 Windows pwsh 路径探测（shell 片段内）

探测顺序：`command -v pwsh.exe` → `/mnt/c/Program Files/PowerShell/7/pwsh.exe` → `/mnt/c/Program Files/PowerShell/6/pwsh.exe`。

**不回退到 Windows PowerShell 5.1**：main.ps1 依赖 pwsh 6+ 特性（`Set-Content -Encoding utf8NoBOM`、`[System.IO.File]::Move` 三参 overwrite 重载），5.1 在写 registry 时会失败。探测全部失败时安静降级、不注册函数。

### D2 仓库根与 UNC 路径解析

解析优先级：
1. 环境变量 `BROWSER_DEBUG_REPO_ROOT`（显式覆盖）；
2. `BASH_SOURCE`/`${(%):-%x}` 所在目录向上找到含 `bin/browser-debug.ps1` 的目录（repo 内 source 场景）；
3. 默认 `$HOME/projects/env/powershellScripts`（deploy.sh 同步到 `~/.bashrc.d/` 后的常规场景）。

UNC 转换用 `wslpath -w`；注册前校验 `bin/browser-debug.ps1` 存在，缺失则安静降级。转换或探测失败不阻断 shell 启动。

### D3 `-ExecutionPolicy Bypass` 注入（runtime.ps1）

`New-BrowserDebugShortcut`（runtime.ps1:587-609）中，当 `$entryPath` 以 `\\` 开头（UNC，即仓库位于 WSL 文件系统）时，快捷方式参数改为：

```
-NoProfile -ExecutionPolicy Bypass -File "<entry>" profile start <name> --mode <mode> --open-guide --yes
```

本地路径场景参数保持不变（现网行为零变更）。理由：RemoteSigned 执行策略视 UNC 为不可信区域，实测无 Bypass 时 UNC 脚本被拦截，创建出的快捷方式双击必失败；Bypass 是让"从 WSL 创建快捷方式"这个目标可用的最小变更。

`Test-BrowserDebugShortcutCurrent`（runtime.ps1:653-672）按子串断言 profile start/--mode/--open-guide/--yes，不受前缀新增影响；现有测试 `tests/BrowserDebugProfile.Tests.ps1:578-593` 使用的均为本地 TestDrive 路径，不会命中 UNC 分支。

### D4 shell 片段合同（沿用 shell-profile-integration.md）

- 先判交互式会话，再判 pwsh 探测与入口文件存在性；不满足安静返回，无硬错误。
- 函数重复注册由会话内标记（如 `__BROWSER_DEBUG_WRAPPER_READY`）阻止。
- 函数内透传 `$@` 与退出码；`--json` 输出原样保留。
- 不注册 bash/zsh 补全（Windows 侧 completion 无法透传给 Linux shell，收益低），列为 out of scope。

### D5 repo-ops reference 定位

新增 `references/wsl-windows-interop.md`：记录已验证的直调契约（探测路径、Bypass 必要性、`wslpath -w` 转换、pwsh 7 硬依赖原因）、mirrored 网络 + `hostAddressLoopback` 下 WSL 可用 `localhost:<cdpPort>` 直连 CDP、可用命令树、验证命令。遵循 repo-ops 规则：不复制产品实现，事实来源指向代码与本文档中的实测命令。

### D6 参数内 POSIX 路径自动转换（shell 片段内）

wrapper 对每个以 `/` 开头且真实存在的参数值执行 `wslpath -w` 后替换，再透传。动机：`--source-user-data-path`、`--profile-path`、`--shortcut-directory`、`--registry-path`、`--ssh-config-path` 的值在 WSL 用户视角是 `/mnt/c/...` 形态。安全性：browser-debug 参数文法中名称值不允许 `/`（`Assert-BrowserDebugName` 拒绝），枚举值均不以 `/` 开头，无误伤面；`wslpath -w` 失败或路径不存在时保持原值透传。`C:\...` 形态值原样透传。

## 数据流与契约

- wrapper 的 stdin/stdout/stderr 直通 Windows pwsh 进程；JSON schema（schemaVersion=1）不变。
- registry、profile 数据、快捷方式内容格式均不变；唯一产物差异是 UNC 场景快捷方式参数多出 `-ExecutionPolicy Bypass`。

## 兼容与回滚

- Windows 本地 checkout 场景：`$entryPath` 非 UNC，行为与今天完全一致。
- 回滚点：shell 片段是新增文件，删除即回滚；runtime.ps1 变更集中在一个参数拼接分支，单 commit 可 revert。
- 风险：用户执行策略若为 AllSigned，Bypass 参数仍会被 -ExecutionPolicy 命令行开关覆盖执行（PowerShell 进程级覆盖，优先于机器策略），双击场景实测可行；`-ExecutionPolicy Bypass` 仅影响该快捷方式拉起的进程，不改变系统策略。
