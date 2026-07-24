# Design: code-host（VS Code Remote CLI 桥接）

## 1. Architecture

```
shell/shared.d/vscode.sh
├─ _code_host_runtime_dir   # runtime 目录
├─ _code_host_find_cli      # 最新 Stable remote-cli/code
├─ _code_host_find_ipc      # 存活 vscode-ipc sock
└─ code-host                # 公共入口：探测 → 单次启动
```

- 经 `deploy.sh` 链到 `~/.bashrc.d/`，Bash/Zsh 同 source。
- 无跨文件依赖；加载顺序无关。
- 不修改全局 `code`、不 `export`。

## 2. Data Flow

```
code-host [args...]
  → find remote-cli binary
  → resolve live IPC sock
       1) 若 $VSCODE_IPC_HOOK_CLI 非空且 --status 成功 → 用它
       2) 否则 ls -t $runtime/vscode-ipc-*.sock，逐个 --status
  → VSCODE_IPC_HOOK_CLI=$ipc "$code_bin" "$@"
  → 返回 remote-cli 退出码
```

失败路径：

| 条件 | 消息要点 | 退出码 |
|---|---|---|
| 无 remote-cli | 无 vscode remote-cli；需先 Remote-SSH 连过一次 | 1 |
| 无存活 sock | 无 live host VS Code Remote-SSH session | 1 |

## 3. Contracts

### `code-host`

- **功能**：在客户端 VS Code 打开路径/执行 remote-cli 子命令。
- **入参**：透传 remote-cli（与官方 `code` remote CLI 相同）。
- **返回值**：成功为 remote-cli 退出码；探测失败为 1。
- **副作用**：无（不 export、不改 PATH）。

### 探测细节

- CLI 路径：`ls -td ~/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code` 取第一个可执行。
- Runtime：`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`。
- 存活判定：`VSCODE_IPC_HOOK_CLI=$sock "$code_bin" --status >/dev/null 2>&1`。
- 前缀赋值限定在调用命令，避免 `export`。

## 4. Compatibility

- Bash 3.2+ / Zsh：用 `[[ ]]`、`local`、`command`、`return`；不用 `mapfile`/zsh 数组特化。
- 多 sock：mtime 新优先，第一个 `--status` 成功即用。
- 多 Stable 版本：mtime 新优先（`ls -td`）。

## 5. Trade-offs

| 选择 | 取 | 舍 |
|---|---|---|
| 独立 `code-host` | 安全、显式 | 不能无脑用 `code` |
| 单次启动无 export | 可预测 | 每次自探测（可接受，探测很轻） |
| 仅 Stable | 简单 | Insiders 用户需后续扩展 |
| `--status` 探测 | 真实存活 | 多 stale sock 时略慢（通常几个） |

## 6. Rollback

删除 `shell/shared.d/vscode.sh` 并重新 `shell/deploy.sh`（或去掉 `~/.bashrc.d/vscode.sh` 链）即可；无状态文件、无迁移。
