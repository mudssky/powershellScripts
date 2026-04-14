# shellcheck shell=bash

if [[ -n "${SSM_CMD_INSTALL_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_INSTALL_LOADED=1

# 当前阶段先完成配置校验与 dry-run 名称输出，为后续真正落盘安装打基础。
ssm_cmd_install() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  [[ -n "${target_kind}" ]] || ssm_die "Missing install target kind"
  [[ -n "${target_name}" ]] || ssm_die "Missing install target name"

  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  case "${target_kind}" in
    service)
      ssm_parse_service_config "${project_dir}" "${target_name}"
      ssm_require_safe_name "UNIT_PREFIX" "${UNIT_PREFIX}"
      printf '%s\n' "$(ssm_service_unit_name "${target_name}")"
      ;;
    timer)
      ssm_parse_timer_config "${project_dir}" "${target_name}"
      ssm_require_safe_name "UNIT_PREFIX" "${UNIT_PREFIX}"
      ssm_resolve_schedule "${SCHEDULE}" >/dev/null
      printf '%s\n' "$(ssm_timer_unit_name "${target_name}")"
      if [[ "${TARGET_TYPE}" == "task" || "${TARGET_TYPE}" == "service" ]]; then
        printf '%s\n' "$(ssm_timer_task_unit_name "${target_name}")"
      fi
      ;;
    *)
      ssm_die "Unknown install target kind: ${target_kind}"
      ;;
  esac
}
