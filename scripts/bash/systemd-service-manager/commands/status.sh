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

  local enabled_state=""
  local active_state=""
  enabled_state="$(ssm_systemctl "${SSM_ACTIVE_SCOPE}" is-enabled "${SSM_ACTIVE_UNIT}" 2>/dev/null || true)"
  active_state="$(ssm_systemctl "${SSM_ACTIVE_SCOPE}" is-active "${SSM_ACTIVE_UNIT}" 2>/dev/null || true)"

  printf 'name=%s\n' "${target_name}"
  printf 'unit=%s\n' "${SSM_ACTIVE_UNIT}"
  printf 'scope=%s\n' "${SSM_ACTIVE_SCOPE}"
  printf 'installed=%s\n' "$(ssm_is_unit_installed "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}")"
  printf 'enabled=%s\n' "${enabled_state:-unknown}"
  printf 'active=%s\n' "${active_state:-unknown}"
}
