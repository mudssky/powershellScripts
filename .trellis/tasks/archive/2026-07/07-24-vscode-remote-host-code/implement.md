# Implement: code-host

## Checklist

- [x] 1. 新建 `shell/shared.d/vscode.sh`
  - [x] 文件头：作用、兼容性、单次启动无副作用说明
  - [x] `_code_host_runtime_dir` / `_code_host_find_cli` / `_code_host_find_ipc`
  - [x] `code-host` 主入口 + 中文注释（功能/入参/返回值）
  - [x] 错误信息可行动；函数恒定义
- [x] 2. 语法检查：`bash -n shell/shared.d/vscode.sh` 通过；本机无 `zsh`，`zsh -n` 未跑
- [x] 3. 手工验证（有 Remote 会话）
  - [x] `env -u VSCODE_IPC_HOOK_CLI ... code-host --status` → exit 0，连上 Windows 客户端
  - [x] stale `VSCODE_IPC_HOOK_CLI` 时仍 exit 0（重扫存活 sock）
  - [x] `code-host .` → exit 0
  - [x] 调用前后 `VSCODE_IPC_HOOK_CLI` / `PATH` 未改；`code` 仍为 remote-cli 路径而非本函数
- [x] 4. 失败路径：`HOME` 无 `.vscode-server` 时错误 `no vscode remote-cli` + exit 1
- [ ] 5. 如已部署环境：按需 `bash shell/deploy.sh` 同步 symlink（未在本会话强制执行）

## Validation Commands

```bash
bash -n shell/shared.d/vscode.sh
# 本机无 zsh 时可跳过：zsh -n shell/shared.d/vscode.sh
bash --noprofile --norc -c 'source shell/shared.d/vscode.sh; code-host --status'
env -u VSCODE_IPC_HOOK_CLI bash --noprofile --norc -c 'source shell/shared.d/vscode.sh; code-host --status'
```

## QA note

`pnpm qa`（changed）触发了既有无关失败：`package-sources` / `package-source-bootstrap`（环境已有 brew mirror 变量）、`claude-profile` editor log。与本文件无关，未改动。

## Risky Files

| 文件 | 风险 | 回滚 |
|---|---|---|
| `shell/shared.d/vscode.sh`（新） | source 语法错误影响交互 shell | 删文件 + redeploy |

## Follow-ups（非本任务）

- `code-host init` 修 PATH/IPC
- Insiders 路径
- `EDITOR=code-host` / fzf 集成
