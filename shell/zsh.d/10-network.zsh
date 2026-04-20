# Tailscale 智能配置（自动检测存在性）
typeset ts_app_path="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
typeset ts_existing_cli_path="$(whence -p tailscale 2>/dev/null || true)"

if [[ -x "$ts_app_path" ]]; then
  typeset -i ts_should_wrap_cli=0

  if [[ -z "$ts_existing_cli_path" ]]; then
    ts_should_wrap_cli=1
  elif [[ -L "$ts_existing_cli_path" ]] && [[ "$(readlink "$ts_existing_cli_path")" == "$ts_app_path" ]]; then
    ts_should_wrap_cli=1
  fi

  if (( ts_should_wrap_cli )); then
    # 独立版 macOS app 的主二进制在普通 shell 上下文里可能误判为 GUI 入口并崩溃。
    # 这里显式强制 CLI 模式，只覆盖“命令缺失”或“仍指向错误软链”的场景，避免影响其他正常安装来源。
    tailscale() {
      TAILSCALE_BE_CLI=1 "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"
    }
  fi
fi

unset ts_app_path ts_existing_cli_path ts_should_wrap_cli
