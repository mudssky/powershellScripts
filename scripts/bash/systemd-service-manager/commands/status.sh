# shellcheck shell=bash

if [[ -n "${SSM_CMD_STATUS_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_STATUS_LOADED=1

# 输出统一状态摘要，便于脚本和人工共同消费。
ssm_cmd_status() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_print_unit_summary "${SSM_ACTIVE_NAME}" "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}"
}
