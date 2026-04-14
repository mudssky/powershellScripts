# shellcheck shell=bash

if [[ -n "${SSM_CMD_LOGS_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_LOGS_LOADED=1

# 查看目标 unit 的 journald 日志，并按需跟随输出。
ssm_cmd_logs() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"

  local -a args=(-u "${SSM_ACTIVE_UNIT}")
  if [[ "${SSM_CLI_FOLLOW}" == "1" ]]; then
    args+=(-f)
  fi
  ssm_journalctl "${SSM_ACTIVE_SCOPE}" "${args[@]}"
}
