# shellcheck shell=bash

if [[ -n "${SSM_CMD_ENABLE_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_ENABLE_LOADED=1

# 启用目标 unit 的自启动。
ssm_cmd_enable() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" enable "${SSM_ACTIVE_UNIT}"
}
