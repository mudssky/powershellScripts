# shellcheck shell=bash

if [[ -n "${SSM_CMD_LIST_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_LIST_LOADED=1

# 清理会由 key-value 配置文件写入的字段，避免上一项配置污染下一项摘要。
# 参数：无。
# 返回值：无返回值。
ssm_list_reset_config_vars() {
  unset DESCRIPTION COMMAND WORKDIR SCOPE RESTART RESTART_SEC WANTED_BY AFTER WANTS
  unset TARGET_TYPE TARGET_NAME ACTION SCHEDULE PERSISTENT RANDOMIZED_DELAY
}

# 转义 JSON 字符串内容，供 list --json 输出稳定结构。
# 参数：$1 为待转义字符串。
# 返回值：向 stdout 输出转义后的字符串内容，不包含外层引号。
ssm_list_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

# 渲染 JSON 字段值；空字符串按 null 输出。
# 参数：$1 为字段值。
# 返回值：向 stdout 输出 JSON 字面量。
ssm_json_value() {
  local value="${1-}"
  if [[ -z "${value}" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(ssm_list_json_escape "${value}")"
  fi
}

# 输出已收集的 JSON 项数组。
# 参数：无，依赖 SSM_LIST_JSON_ITEMS。
# 返回值：无返回值。
ssm_list_print_json() {
  local index=0
  printf '['
  while [[ "${index}" -lt "${#SSM_LIST_JSON_ITEMS[@]}" ]]; do
    if [[ "${index}" -gt 0 ]]; then
      printf ','
    fi
    printf '%s' "${SSM_LIST_JSON_ITEMS[${index}]}"
    index=$((index + 1))
  done
  printf ']\n'
}

# 解析并输出单个 service 摘要。
# 参数：$1 为项目目录，$2 为服务名，$3 为输出模式：0 文本、1 JSON。
# 返回值：成功返回 0；配置非法时由 parser 终止。
ssm_list_emit_service() {
  local project_dir="$1"
  local service_name="$2"
  local output_json="$3"

  ssm_list_reset_config_vars
  ssm_parse_service_config "${project_dir}" "${service_name}"

  if [[ "${output_json}" -eq 1 ]]; then
    SSM_LIST_JSON_ITEMS+=("{\"type\":\"service\",\"name\":$(ssm_json_value "${service_name}"),\"scope\":$(ssm_json_value "${SSM_SERVICE_SCOPE}"),\"command\":$(ssm_json_value "${COMMAND:-}"),\"restart\":$(ssm_json_value "${RESTART:-on-failure}"),\"restartSec\":$(ssm_json_value "${RESTART_SEC:-5s}"),\"schedule\":null,\"targetType\":null,\"targetName\":null,\"action\":null}")
    return 0
  fi

  printf -- '- %s | scope=%s | restart=%s/%s | command=%s\n' \
    "${service_name}" "${SSM_SERVICE_SCOPE}" "${RESTART:-on-failure}" "${RESTART_SEC:-5s}" "${COMMAND:-}"
}

# 解析并输出单个 timer 摘要。
# 参数：$1 为项目目录，$2 为 timer 名，$3 为输出模式：0 文本、1 JSON。
# 返回值：成功返回 0；配置非法时由 parser 终止。
ssm_list_emit_timer() {
  local project_dir="$1"
  local timer_name="$2"
  local output_json="$3"

  ssm_list_reset_config_vars
  ssm_parse_timer_config "${project_dir}" "${timer_name}"

  if [[ "${output_json}" -eq 1 ]]; then
    local timer_command="${COMMAND:-}"
    if [[ "${TARGET_TYPE}" == "service" ]]; then
      timer_command=""
    fi
    SSM_LIST_JSON_ITEMS+=("{\"type\":\"timer\",\"name\":$(ssm_json_value "${timer_name}"),\"scope\":$(ssm_json_value "${SSM_TIMER_SCOPE}"),\"command\":$(ssm_json_value "${timer_command}"),\"restart\":null,\"restartSec\":null,\"schedule\":$(ssm_json_value "${SCHEDULE}"),\"targetType\":$(ssm_json_value "${TARGET_TYPE}"),\"targetName\":$(ssm_json_value "${TARGET_NAME:-}"),\"action\":$(ssm_json_value "${ACTION:-}")}")
    return 0
  fi

  if [[ "${TARGET_TYPE}" == "service" ]]; then
    printf -- '- %s | scope=%s | schedule=%s | target=service:%s | action=%s\n' \
      "${timer_name}" "${SSM_TIMER_SCOPE}" "${SCHEDULE}" "${TARGET_NAME}" "${ACTION:-restart}"
  else
    printf -- '- %s | scope=%s | schedule=%s | target=task | command=%s\n' \
      "${timer_name}" "${SSM_TIMER_SCOPE}" "${SCHEDULE}" "${COMMAND:-}"
  fi
}

# 列出项目中的服务与 timer；支持文本摘要和稳定 JSON 输出。
# 参数：支持 --json，其余项目路径等公共参数由 CLI 层提前解析。
# 返回值：成功返回 0；未知参数或配置非法时退出 1。
ssm_cmd_list() {
  local output_json=0
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --json)
        output_json=1
        shift
        ;;
      *)
        ssm_die "Unknown list option: $1"
        ;;
    esac
  done

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

  SSM_LIST_JSON_ITEMS=()

  if [[ "${output_json}" -eq 0 ]]; then
    printf 'Services\n'
  fi

  local service_file
  for service_file in "$(ssm_config_root "${project_dir}")"/services/*.conf; do
    [[ -f "${service_file}" ]] || continue
    ssm_list_emit_service "${project_dir}" "$(basename "${service_file}" .conf)" "${output_json}"
  done

  if [[ "${output_json}" -eq 0 ]]; then
    printf 'Timers\n'
  fi

  local timer_file
  for timer_file in "$(ssm_config_root "${project_dir}")"/timers/*.conf; do
    [[ -f "${timer_file}" ]] || continue
    ssm_list_emit_timer "${project_dir}" "$(basename "${timer_file}" .conf)" "${output_json}"
  done

  if [[ "${output_json}" -eq 1 ]]; then
    ssm_list_print_json
  fi
}
