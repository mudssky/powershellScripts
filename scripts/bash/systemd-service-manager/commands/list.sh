# shellcheck shell=bash

if [[ -n "${SSM_CMD_LIST_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_LIST_LOADED=1

# 列出项目中的服务与 timer；测试模式下额外打印解析后的关键字段。
ssm_cmd_list() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  ssm_load_project_config "${project_dir}"

  if [[ "${SSM_DEBUG_DUMP_CONFIG:-}" == "1" ]]; then
    if [[ -f "$(ssm_service_config_path "${project_dir}" "api")" ]]; then
      ssm_parse_service_config "${project_dir}" "api"
      ssm_collect_env_entries_for_service "${project_dir}" "api"
    fi
    printf 'project=%s\n' "${SSM_PROJECT_NAME}"
    printf 'scope=%s\n' "${SSM_SERVICE_SCOPE:-${DEFAULT_SCOPE:-system}}"
    printf 'APP_PORT=%s\n' "$(ssm_get_env_entry_value "APP_PORT")"
    printf 'APP_NAME=%s\n' "$(ssm_get_env_entry_value "APP_NAME")"
    return 0
  fi

  printf 'Services\n'
  local service_file
  for service_file in "$(ssm_config_root "${project_dir}")"/services/*.conf; do
    [[ -f "${service_file}" ]] || continue
    printf -- '- %s\n' "$(basename "${service_file}" .conf)"
  done

  printf 'Timers\n'
  local timer_file
  for timer_file in "$(ssm_config_root "${project_dir}")"/timers/*.conf; do
    [[ -f "${timer_file}" ]] || continue
    printf -- '- %s\n' "$(basename "${timer_file}" .conf)"
  done
}
