# Design — browser-debug macOS/Linux 支持

## 架构与边界

保持现有 CLI 命令树与 JSON 输出合同不变，在 `scripts/pwsh/devops/browser-debug/runtime.ps1` 内引入按 OS 分派的能力层（不新建子目录，避免文件拆散既有 dot-source 结构）：

```text
main.ps1 (平台门禁改写)
  └─ commands.ps1 (编排不变，仅平台感知点替换)
       └─ runtime.ps1
            ├─ 平台判定: Get-BrowserDebugPlatform -> windows|macos|linux
            ├─ 浏览器发现: Resolve-BrowserDebugExecutable        (按平台路径表)
            ├─ User Data:  Resolve-BrowserDebugDefaultUserDataPath (按平台路径表)
            ├─ 克隆:       Copy-BrowserDebugUserData             (robocopy|ditto|cp -a 分派)
            ├─ 进程枚举:   Get-BrowserDebugChromiumProcesses     (Win32_Process|ps 解析)
            ├─ 快捷方式:   New-BrowserDebugShortcut              (.lnk|.command|.desktop 分派)
            └─ 其余 (CDP 探测/guide/registry/stop-owned) 平台无关复用
```

## 各平台能力表

| 能力 | Windows（现状不动） | macOS | Linux |
|---|---|---|---|
| chrome 可执行 | `ProgramFiles\Google\Chrome\Application\chrome.exe` | `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`、`~/Applications` 同构 | PATH 中 `google-chrome` / `google-chrome-stable` |
| edge 可执行 | `ProgramFiles\Microsoft\Edge\Application\msedge.exe` | `/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge` | PATH 中 `microsoft-edge` / `microsoft-edge-stable` |
| chrome User Data | `LOCALAPPDATA\Google\Chrome\User Data` | `~/Library/Application Support/Google/Chrome` | `~/.config/google-chrome` |
| edge User Data | `LOCALAPPDATA\Microsoft\Edge\User Data` | `~/Library/Application Support/Microsoft Edge` | `~/.config/microsoft-edge` |
| 锁排除 | `lockfile` | `SingletonLock` `SingletonSocket` `SingletonCookie` | 同 macOS |
| 克隆 | `robocopy /E /COPY:DAT ...`，退出码 0..7 | `ditto <src> <dst>`，退出码 0 | `cp -a <src>/. <dst>/`，退出码 0 |
| 进程命令行 | `Get-CimInstance Win32_Process` | `ps -axo pid=,args=`（`/bin/ps`） | `ps -e -o pid=,args=` |
| 快捷方式 | WScript `.lnk`（win.psm1） | `<name>.command`（shell 脚本，`chmod +x`，shebang 执行 pwsh） | `<name>.desktop`（`Exec=pwsh ...`，`Terminal=false`，`Type=Application`） |
| 快捷方式目录 | 桌面 | 桌面（`[Environment]::GetFolderPath(Desktop)`） | XDG 桌面目录（存在时）+ `~/.local/share/applications` |
| stop | `Stop-Process`（owned PID） | `kill <pid>`（SIGTERM） | 同 macOS |

## 关键设计点

### 1. 平台门禁改写（main.ps1 / runtime.ps1:10-14）

`Assert-BrowserDebugWindowsPlatform` 拆为能力检查：`completion`、`help`、`profile list/get` 保持全平台可用；`profile create/start/status/stop/shortcut` 在三平台可用（local 模式）；`--mode lan` 与 `ssh *` 在非 Windows 抛"仅 Windows 支持"并保持现有错误输出合同（文本/`--json` 两种形态）。Windows 上不再新增行为。

### 2. 路径语义

- 默认数据根（D4）：Unix 用 `[Environment]::GetFolderPath(LocalApplicationData)/browser-debug-profiles`，替换 `D:\` 默认值与 `commands.ps1:142`、`registry.ps1:102` 的 `D:\` 特判（改为"默认根不可写时要求显式 --registry-path/--profile-path"的通用文案）。
- 大小写：新增 `Compare-BrowserDebugPath`，Linux 用 `Ordinal`，Windows/macOS 用 `OrdinalIgnoreCase`；替换现有 `TrimEnd('\') + OrdinalIgnoreCase` 比较（`commands.ps1:129,138`），分隔符交给 `GetFullPath`。

### 3. Unix 进程枚举与 owned 判定

`ps` 输出解析为 `{ ProcessId, ExecutablePath, CommandLine }` 形状，与现有 Windows 对象形状对齐，使 `Get-BrowserDebugOwnedChromiumProcesses`、`--remote-debugging-port=` 端口提取、`--user-data-dir=` 正则（`runtime.ps1:121-132,374-404`）原样复用。正则按 Unix 路径无引号形态放宽匹配（保留既有引号分支）。

### 4. 快捷方式合同（对齐 .lnk 语义）

- 文件名：local 为 `<name>.command` / `<name>.desktop`（MVP 无 `-LAN` 变体）；内容含 `profile start "<name>" --mode local --open-guide --yes`，`Test-BrowserDebugShortcutCurrent` 改为读平台文件内容而非 WScript COM（Windows 分支保持 `.lnk` 读取）。
- 幂等/事务：沿用 `Add-BrowserDebugProfileShortcut` 的临时文件→原子改名→registry 提交→备份清理事务，仅把"内容生成与合同校验"抽出平台回调；未知同名文件拒绝覆盖合同不变。
- macOS `.command` 内容：`#!/bin/sh` + `exec pwsh -NoProfile -File "<entry>" ...`，`chmod +x`；图标无对应物（Terminal 默认），接受此差异。
- Linux `.desktop`：`Exec` 行按 freedesktop 转义；写入后尝试 `update-desktop-database`（失败仅 warning，同 guide 失败语义）。

### 5. registry schema

`schemaVersion` 保持 1：新增字段均为可选（profile 无需平台字段，`browserPath` 本身已记录平台路径）；旧 registry 文件跨平台迁移无需转换。

### 6. 测试策略

- Linux Docker harness（现有 `pnpm test:pwsh:all`）原生覆盖 Unix 分支：stub 浏览器可执行文件放 `$TestDrive`、env 覆盖发现路径，真跑 `ps` 解析、`.desktop`/`.command` 生成、克隆排除（`cp -a` 分支）。`ditto` 分支在 Linux 上以 mock 验证参数合同。
- Windows 分支：现有 855 行契约测试全部保留并保持绿色，作为零回归守护。
- guide 模板与 LAN 文案不动（LAN 仅 Windows，文案合同不变）。

### 7. Unix detached 启动（实机验收发现的补充设计）

实现中发现：.NET `Process.Start` 在 Unix 上不创建新会话，子进程留在父进程组；pwsh CLI 退出（尤其终端会话关闭）时浏览器收到 SIGHUP 被级联关闭（GPU 子进程 exit_code=15 的优雅关闭链）。修复：`Start-BrowserDebugDetachedProcess` 的 Unix 分支经 `/bin/sh -c "exec nohup <browser> <args> </dev/null >/dev/null 2>&1"` 启动——nohup 忽略 SIGHUP，stdio 全部脱离控制终端，双重 `exec` 保持返回的 PID 就是浏览器主进程 PID。Windows 分支保持原 `ArgumentList` 直启不变。

### 8. 默认端口与 pwsh 入口探测（第二轮实机反馈）

- 默认 CDP 端口按用户决策三平台统一为 21229（原 9222 与用户本机常驻 Chromium 冲突）。
- macOS Homebrew 下 `Get-Command pwsh` 首个匹配可能是 Cellar 内需要 `DOTNET_ROOT` 的裸 apphost，双击 `.command`（无 shell 环境）时直接失败。修复：`Get-BrowserDebugRunnablePwshPath` 对候选逐一试运行 `-NoProfile -Command exit 0`，取退出码 0 者；`completion.ps1` 注册补全时不再固化 Source，调用时按当前会话 PATH 解析 `pwsh`。

## 权衡记录

- `.command` 双击会弹 Terminal 窗口：MVP 接受，换取零 plist/签名复杂度；`.app` 形态列为后续增强。
- Linux 双写（桌面 + applications 目录）：GNOME 桌面图标默认隐藏且需"允许启动"，applications 目录是可靠的启动入口；两者都写，registry 登记实际路径。
- 克隆不用 pwsh `Copy-Item -Recurse`：User Data 数 GB 小文件场景过慢；`ditto`/`cp -a` 均为系统自带。

## 回滚

改动集中在 `runtime.ps1`/`main.ps1`/`commands.ps1`/registry 默认值与测试，单提交可 revert；registry 格式无迁移，回滚后旧版本仍可读新 registry。
