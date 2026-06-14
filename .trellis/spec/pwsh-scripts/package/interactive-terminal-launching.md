# PowerShell Interactive Terminal Launching Spec

> 本规范记录 `scripts/pwsh/**` 启动 SSH、WSL、zellij 等交互式原生命令时的终端承载契约。核心原则是：交互式会话必须独占一个前台终端；想让包装脚本立即返回，就要把会话放到新终端或明确 detached 进程，而不是在当前 tab 里后台化。

## Scenario: Interactive SSH/WSL Session Launching

### 1. Scope / Trigger

- Trigger: 修改 `scripts/pwsh/**` 中启动长生命周期交互式命令的逻辑，例如 `ssh`、`wsl.exe -- bash -lc ...`、`zellij attach`、远端 shell 或 TUI 会话。
- Scope: 包装脚本负责选择承载模式、生成参数数组、保留诊断输出和返回 detached 状态；真实 SSH 连接语义仍交给 OpenSSH，真实 WSL 命令语义仍交给 `wsl.exe` 与 Linux shell。
- Design intent: 避免 fzf/PowerShell 包装器启动交互式会话后看似卡住、`Ctrl+C` 被远端进程消费、或 Windows Terminal 把 shell 片段误解析成多个 tab 命令。

### 2. Signatures

- Inline execution:
  - `& $Plan.Executable @($Plan.Arguments)`
  - The wrapper waits until the interactive child exits.
- Detached Windows Terminal execution:
  - `wt.exe -w 0 new-tab --title <title> pwsh -NoLogo -NoProfile -NoExit -File <temp-script.ps1>`
  - The wrapper starts the terminal process and returns without waiting for SSH/WSL.
- Detached fallback execution:
  - `pwsh -NoLogo -NoProfile -NoExit -File <temp-script.ps1>`
  - Used when `wt.exe` is unavailable.
- SSH plan:
  - `ssh -tt <HostAlias>`
  - If SSH config has `RequestTTY no`, use `ssh <HostAlias>`.
- WSL plan:
  - `wsl.exe -d <Distro> -- bash -lc <Command>`

### 3. Contracts

- A current-tab interactive launch is an inline launch. The wrapper must wait for the child process to exit because PowerShell and SSH/WSL cannot reliably share the same terminal input stream at the same time.
- A wrapper that should return immediately must start the interactive child in another terminal session, such as Windows Terminal new tab or a new PowerShell console.
- Detached launches must report that they are detached and should not treat the child session's final exit code as the wrapper's synchronous exit code.
- Build native command arguments as arrays. Do not flatten `wsl.exe` or `ssh` arguments into one command-line string unless the target API only accepts a string.
- For Windows Terminal, do not pass complex `pwsh -Command "...; if (...)"` payloads directly to `wt.exe`. Windows Terminal treats semicolons as command separators in its own command grammar, which can open extra tabs or try to execute broken fragments.
- Use a temporary `.ps1` file with `pwsh -NoExit -File <temp-script>` when a detached terminal needs post-exit diagnostics or cleanup. The temporary script should call the native executable with an argument array.
- SSH launchers that discover entries from SSH config should launch by Host alias, not by reconstructing `HostName`、`User`、`Port` and `RemoteCommand`. This keeps OpenSSH as the final authority for connection behavior.
- Interactive SSH entries should allocate a TTY by default with `-tt`; respect `RequestTTY no` when the user's SSH config explicitly disables TTY allocation.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| User chooses inline/current-tab mode | Wrapper prints the command, starts the native process, waits for it to exit, then returns the native exit code |
| User chooses default Windows interactive mode | Wrapper opens Windows Terminal new tab, returns detached result, and does not wait for SSH/WSL |
| `wt.exe` is unavailable | Wrapper opens a standalone PowerShell console with the same temp script contract |
| SSH config has `RequestTTY no` | Plan uses `ssh <HostAlias>` without `-tt` |
| SSH config omits `RequestTTY` | Plan uses `ssh -tt <HostAlias>` |
| WSL command contains semicolon, quotes, or shell operators | Command remains one `bash -lc <Command>` argument inside the temp script/native argument array |
| Detached terminal cannot be started | Surface the `Start-Process` or `Process.Start` error; do not silently fall back to inline interactive execution |

### 5. Good/Base/Bad Cases

- Good: `scripts/pwsh/devops/project-launcher/main.ps1` opens SSH/WSL in Windows Terminal by default and offers `-Inline` only when the user explicitly wants the current tab to be occupied.
- Good: Detached Windows Terminal uses `pwsh -NoExit -File <temp-script>` so command fragments are not reinterpreted by `wt.exe`.
- Good: SSH execution plans use `ssh -tt <HostAlias>` while still leaving HostName/User/Port/RemoteCommand resolution to OpenSSH.
- Base: A non-interactive child command may be run inline and waited on because it does not need ongoing terminal ownership.
- Bad: Start `ssh` in the current tab and immediately return to the PowerShell prompt. PowerShell and SSH will both try to read from the same console.
- Bad: Send `pwsh -Command "& ssh host; if ($LASTEXITCODE) { ... }"` directly through `wt.exe`; the semicolon can be parsed as a Windows Terminal command separator.

### 6. Tests Required

- Execution-plan tests must assert SSH defaults to `-tt` and honors `RequestTTY no`.
- Platform behavior tests must assert Windows interactive SSH/WSL uses detached terminal mode by default and `-Inline` bypasses terminal spawning.
- Windows Terminal argument tests must assert the generated argument list contains `new-tab` and `-File <temp-script>`, not a complex `-Command` payload.
- Native process tests should mock terminal path resolution and process start boundaries instead of launching real SSH/WSL.
- Dry-run tests must assert no terminal or native process is started.
- When temp-script generation is changed, add tests that assert arguments are represented as arrays in the script content and that shell command text remains a single argument where needed.

### 7. Wrong vs Correct

#### Wrong

```powershell
Start-Process wt.exe -ArgumentList @(
    'new-tab',
    'pwsh',
    '-NoExit',
    '-Command',
    '& ssh AI-admin; if ($LASTEXITCODE) { Write-Host "failed" }'
)
```

问题：`wt.exe` 有自己的命令分隔语义，分号可能导致额外 tab 或错误片段被当成可执行文件启动；同时复杂 quoting 会穿过 PowerShell、Windows Terminal 和目标 shell 多层解释。

#### Correct

```powershell
$scriptPath = New-TemporaryFilePath
$terminalArguments = @(
    '-w', '0',
    'new-tab',
    '--title', 'AI-admin',
    'pwsh',
    '-NoLogo',
    '-NoProfile',
    '-NoExit',
    '-File',
    $scriptPath
)
Start-NativeProcess -FilePath 'wt.exe' -ArgumentList $terminalArguments
```

理由：Windows Terminal 只接收稳定的 tab 与 PowerShell 文件参数，真实 SSH/WSL 参数在临时脚本内以数组方式调用，避免跨 shell quoting 漂移。
