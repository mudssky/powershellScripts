# shellcheck shell=bash

if [[ -n "${SSM_CMD_STOP_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_STOP_LOADED=1

# 停止目标 unit。
ssm_cmd_stop() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" stop "${SSM_ACTIVE_UNIT}"
}
