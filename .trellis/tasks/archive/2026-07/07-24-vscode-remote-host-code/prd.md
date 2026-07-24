# VS Code Remote 终端 code 客户端打开

## Goal

在 Remote-SSH 远程机上的 Bash/Zsh 终端提供 `code-host`：**直接**调用 `vscode-server` 的 `remote-cli/code`，配合存活 IPC socket，在**客户端 VS Code** 打开文件/目录/跳转行。

用户价值：plain SSH / tmux / 外部终端等未注入 VS Code 环境的会话里，也能把路径送回本机 VS Code。

## Background

- 落地：`shell/shared.d/vscode.sh`，经 `shell/deploy.sh` → `~/.bashrc.d/`，Bash/Zsh 共用。
- 规范：`.trellis/spec/shell-shared/package/index.md`（双 shell、函数恒定义、领域单文件、中文注释、手工验证）。
- 参考：探测最新 `~/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code` + 存活 `vscode-ipc-*.sock`，设置 `VSCODE_IPC_HOOK_CLI` 后 `"$@"` 转发。
- 实测（2026-07-24）：remote-cli 与多个 ipc sock 存在；集成终端常已注入 env；缺口在非注入会话与 stale IPC。
- 禁止硬编码 `/run/user/1000`；用 `$XDG_RUNTIME_DIR` 或 `/run/user/$(id -u)`。
- 仓库无既有封装；不覆盖系统 `code`。

## Key Decisions

| 决策 | 选择 | 理由 |
|---|---|---|
| 入口 | `code-host` | 用户指定 |
| 与 `code` 关系 | 不覆盖、不 alias | 显式桥接；避免冲突 |
| 调用语义 | **直接启动** remote-cli（单次） | 用户确认；不做 env 修复 / `init` 子命令 |
| 会话副作用 | 无：不 `export`、不改 `PATH` | 仅本次进程环境 |
| 文件 | `shell/shared.d/vscode.sh` | 领域单文件 |

## Requirements

- R1: 新增 `shell/shared.d/vscode.sh`，定义 `code-host`。
- R2: 发现最新可执行 Stable `remote-cli/code`（`~/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code`）。
- R3: 发现存活 IPC：优先校验已有 `VSCODE_IPC_HOOK_CLI`；否则在 runtime 目录按 mtime 扫描 `vscode-ipc-*.sock`，用 `code --status` 探测。
- R4: runtime 目录 = `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`。
- R5: 缺 remote-cli / 无存活 sock → stderr 可行动错误 + 非 0；函数始终定义。
- R6: `code-host "$@"` 透传参数（`.`、`file`、`-g path:line` 等）。
- R7: Bash/Zsh 兼容；加载顺序无关。
- R8: 公共入口与关键辅助带规范中文注释。

## Acceptance Criteria

- [ ] AC1: 有活跃 Remote-SSH、shell 未注入 `VSCODE_IPC_HOOK_CLI` 时，`code-host .` 在客户端打开当前目录。
- [ ] AC2: 环境变量 sock 失效且仍有其它存活 sock 时，重新扫描后成功。
- [ ] AC3: 无 remote-cli 或无存活 sock 时，明确错误 + 非 0。
- [ ] AC4: `code-host -g path:line` / `code-host file` 与 remote-cli 行为一致。
- [ ] AC5: `bash -n` / `zsh -n` 通过；source 后可调用。
- [ ] AC6: 本文件不把 `code` 变成 alias/function。
- [ ] AC7: 成功调用后当前 shell 的 `VSCODE_IPC_HOOK_CLI` / `PATH` 不被本函数改写（单次启动语义）。
- [ ] AC8: 未改 PowerShell / `profile/**`；靠 `deploy.sh` 同步。

## Out of Scope

- PowerShell / 本机 Windows `code` 包装
- 安装/升级 `vscode-server`
- 覆盖 `code`、export 环境、`code-host init`
- Cursor / VSCodium / code-server 专项适配
- 改 `EDITOR` / `fzf-open` 默认
- 自动化测试框架

## Technical Notes

- 探测与执行都在函数内完成；`VSCODE_IPC_HOOK_CLI=... "$code_bin" "$@"` 前缀赋值，避免污染 shell。
- Stable 优先；Insiders 不主动扩展除非零成本。
- 验证：手工 + `bash -n`/`zsh -n`；`pnpm qa` 不覆盖 shared.d。
