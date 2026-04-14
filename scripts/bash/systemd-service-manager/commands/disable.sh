# shellcheck shell=bash

if [[ -n "${SSM_CMD_DISABLE_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_DISABLE_LOADED=1

# 禁用目标 unit 的自启动。
ssm_cmd_disable() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" disable "${SSM_ACTIVE_UNIT}"
  printf 'disabled=%s\n' "${SSM_ACTIVE_UNIT}"
  ssm_print_unit_summary "${SSM_ACTIVE_NAME}" "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}"
}
