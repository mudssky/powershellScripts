# ======================================================================
# 文件：10-network.zsh
# 作用：在 Tailscale macOS App CLI 可用时提供稳定的命令包装。
# 兼容性：仅 Zsh；Tailscale macOS App。
# ======================================================================

# -- tailscale cli ------------------------------------------------------
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
    # ----------------------------------------------------------------------
    # tailscale — 使用 macOS App 内置二进制执行 Tailscale CLI 命令。
    #
    # 设计意图：
    #   仅在命令缺失或软链仍指向 App 二进制时包装，避免影响其它正常安装来源。
    #
    # 参数：$@ — 原样传递给 Tailscale CLI。
    # 返回码：透传 Tailscale CLI 的退出码。
    # ----------------------------------------------------------------------
    tailscale() {
      TAILSCALE_BE_CLI=1 "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"
    }
  fi
fi

unset ts_app_path ts_existing_cli_path ts_should_wrap_cli
