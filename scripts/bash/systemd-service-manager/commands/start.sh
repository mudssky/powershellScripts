# shellcheck shell=bash

if [[ -n "${SSM_CMD_START_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_START_LOADED=1

# 启动目标 unit，scope 由目标配置决定。
ssm_cmd_start() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" start "${SSM_ACTIVE_UNIT}"
}
