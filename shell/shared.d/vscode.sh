# ========================================================================
# 文件: vscode.sh
# 作用: 在 VS Code Remote-SSH 远程机上，通过 remote-cli + 存活 IPC，
#       把 code-host 调用直接送到客户端 VS Code 打开文件/目录。
# 兼容: Bash / Zsh（shared.d 双 shell 共用）
# 语义: 单次启动，不 export、不改 PATH、不覆盖系统 code。
# ========================================================================

# 输出 code-host 错误信息。
# 参数：$@ 为错误消息。
# 返回值：总是返回 0。
_code_host_error() {
  printf '[code-host] %s\n' "$*" >&2
}

# 返回 VS Code IPC 所在 runtime 目录。
# 参数：无。
# 返回值：输出目录路径并返回 0。
_code_host_runtime_dir() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
}

# 查找最新可用的 Stable remote-cli/code。
# 参数：无。
# 返回值：成功时 stdout 输出可执行路径并返回 0；否则返回 1。
_code_host_find_cli() {
  local candidate

  # ls -td：按修改时间新→旧；取第一个可执行文件。
  for candidate in $(ls -td "$HOME"/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code 2>/dev/null); do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# 在给定 remote-cli 下查找存活的 VSCODE_IPC_HOOK_CLI socket。
# 参数：$1 为 remote-cli/code 可执行路径。
# 返回值：成功时 stdout 输出 sock 路径并返回 0；否则返回 1。
_code_host_find_ipc() {
  local code_bin="$1"
  local runtime_dir sock

  if [[ -z "$code_bin" || ! -x "$code_bin" ]]; then
    return 1
  fi

  # 优先复用当前环境里已注入且仍存活的 sock。
  if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]]; then
    if VSCODE_IPC_HOOK_CLI="$VSCODE_IPC_HOOK_CLI" "$code_bin" --status >/dev/null 2>&1; then
      printf '%s\n' "$VSCODE_IPC_HOOK_CLI"
      return 0
    fi
  fi

  runtime_dir="$(_code_host_runtime_dir)"
  # 按 mtime 新→旧探测；--status 成功即视为客户端 Remote 会话存活。
  for sock in $(ls -t "$runtime_dir"/vscode-ipc-*.sock 2>/dev/null); do
    if VSCODE_IPC_HOOK_CLI="$sock" "$code_bin" --status >/dev/null 2>&1; then
      printf '%s\n' "$sock"
      return 0
    fi
  done

  return 1
}

# 在客户端 VS Code 打开路径或执行 remote-cli 子命令（单次启动，无 shell 副作用）。
# 参数：$@ 透传给 remote-cli/code（如 .、file、-g path:line）。
# 返回值：成功时为 remote-cli 退出码；探测失败返回 1。
code-host() {
  local code_bin ipc

  code_bin="$(_code_host_find_cli)" || {
    _code_host_error "no vscode remote-cli; connect once via VS Code Remote-SSH first"
    return 1
  }

  ipc="$(_code_host_find_ipc "$code_bin")" || {
    _code_host_error "no live host VS Code Remote-SSH session"
    return 1
  }

  # 前缀赋值仅作用于本次调用，不 export 到当前 shell。
  VSCODE_IPC_HOOK_CLI="$ipc" "$code_bin" "$@"
}
