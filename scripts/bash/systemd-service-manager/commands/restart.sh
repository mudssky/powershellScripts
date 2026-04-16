# shellcheck shell=bash

if [[ -n "${SSM_CMD_RESTART_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_RESTART_LOADED=1

# 重启目标 unit。
ssm_cmd_restart() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" restart "${SSM_ACTIVE_UNIT}"
  printf 'restarted=%s\n' "${SSM_ACTIVE_UNIT}"
  ssm_print_unit_summary "${SSM_ACTIVE_NAME}" "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}"
}
