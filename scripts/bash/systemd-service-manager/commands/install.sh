# shellcheck shell=bash

if [[ -n "${SSM_CMD_INSTALL_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_INSTALL_LOADED=1

# 当前阶段先完成配置校验与 dry-run 名称输出，为后续真正落盘安装打基础。
ssm_cmd_install() {
  local target_kind="${1:-}"
  local target_name="${2:-}"
  [[ -n "${target_kind}" ]] || ssm_die "Missing install target"

  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"
  ssm_resolve_target_spec "${project_dir}" "${target_kind}" "${target_name}"
  local render_dir
  render_dir="$(mktemp -d)"
  trap 'rm -rf '"'"${render_dir}"'"'' RETURN

  local source_file=""
  local scope="system"

  case "${SSM_RESOLVED_TARGET_KIND}" in
    service)
      ssm_parse_service_config "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}"
      ssm_require_safe_name "UNIT_PREFIX" "${UNIT_PREFIX}"
      source_file="$(ssm_service_config_path "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}")"
      scope="${SSM_SERVICE_SCOPE}"
      local service_unit_file="${render_dir}/$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      ssm_render_service_unit "${source_file}" >"${service_unit_file}"
      ssm_verify_unit_file "${service_unit_file}" || ssm_die "systemd-analyze verify failed for ${service_unit_file}"
      if [[ "${SSM_CLI_DRY_RUN}" == "1" ]]; then
        printf '%s\n' "$(basename "${service_unit_file}")"
        return 0
      fi
      mkdir -p "$(ssm_unit_dir_for_scope "${scope}")"
      cp "${service_unit_file}" "$(ssm_unit_dir_for_scope "${scope}")/"
      ssm_daemon_reload "${scope}"
      printf 'installed=%s\n' "$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      if [[ "${SSM_CLI_START_AFTER_INSTALL}" == "1" ]]; then
        ssm_systemctl "${scope}" start "$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
        printf 'started=%s\n' "$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      fi
      ssm_print_unit_summary "${SSM_RESOLVED_TARGET_NAME}" "${scope}" "$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      ;;
    timer)
      ssm_parse_timer_config "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}"
      ssm_require_safe_name "UNIT_PREFIX" "${UNIT_PREFIX}"
      source_file="$(ssm_timer_config_path "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}")"
      scope="${SSM_TIMER_SCOPE}"
      local schedule_block
      schedule_block="$(ssm_resolve_schedule "${SCHEDULE}")"
      local task_unit_name
      task_unit_name="$(ssm_timer_task_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      local task_unit_file="${render_dir}/${task_unit_name}"
      local timer_unit_file="${render_dir}/$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      local task_exec_command=""

      if [[ "${TARGET_TYPE}" == "service" ]]; then
        local target_unit
        target_unit="$(ssm_service_unit_name "${TARGET_NAME}")"
        if [[ "${scope}" == "user" ]]; then
          task_exec_command="/usr/bin/env bash -lc 'systemctl --user ${ACTION:-restart} ${target_unit}'"
        else
          task_exec_command="/usr/bin/env bash -lc 'systemctl ${ACTION:-restart} ${target_unit}'"
        fi
      else
        task_exec_command="${COMMAND}"
      fi

      ssm_render_task_service_unit "${source_file}" "${task_exec_command}" >"${task_unit_file}"
      ssm_render_timer_unit "${source_file}" "${task_unit_name}" "${schedule_block}" >"${timer_unit_file}"
      ssm_verify_unit_file "${task_unit_file}" || ssm_die "systemd-analyze verify failed for ${task_unit_file}"
      ssm_verify_unit_file "${timer_unit_file}" || ssm_die "systemd-analyze verify failed for ${timer_unit_file}"

      if [[ "${SSM_CLI_DRY_RUN}" == "1" ]]; then
        printf '%s\n' "$(basename "${timer_unit_file}")"
        printf '%s\n' "$(basename "${task_unit_file}")"
        return 0
      fi

      mkdir -p "$(ssm_unit_dir_for_scope "${scope}")"
      cp "${task_unit_file}" "$(ssm_unit_dir_for_scope "${scope}")/"
      cp "${timer_unit_file}" "$(ssm_unit_dir_for_scope "${scope}")/"
      ssm_daemon_reload "${scope}"
      printf 'installed=%s\n' "$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      if [[ "${SSM_CLI_START_AFTER_INSTALL}" == "1" ]]; then
        ssm_systemctl "${scope}" start "$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
        printf 'started=%s\n' "$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      fi
      ssm_print_unit_summary "${SSM_RESOLVED_TARGET_NAME}" "${scope}" "$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      ;;
    *)
      ssm_die "Unknown install target kind: ${target_kind}"
      ;;
  esac
}
