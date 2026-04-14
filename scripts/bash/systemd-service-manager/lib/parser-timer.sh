# shellcheck shell=bash

if [[ -n "${SSM_TIMER_PARSER_LOADED:-}" ]]; then
  return 0
fi
SSM_TIMER_PARSER_LOADED=1

# 解析单个 timer 配置，并校验它引用的服务目标是否存在。
ssm_parse_timer_config() {
  local project_dir="$1"
  local timer_name="$2"
  local timer_file
  timer_file="$(ssm_timer_config_path "${project_dir}" "${timer_name}")"

  [[ -f "${timer_file}" ]] || ssm_die "Missing timer config: ${timer_file}"

  ssm_load_project_config "${project_dir}"
  ssm_load_key_value_file "${timer_file}"
  ssm_load_timer_env "${project_dir}" "${timer_name}"

  [[ -n "${TARGET_TYPE:-}" ]] || ssm_die "Missing TARGET_TYPE in ${timer_file}"
  [[ -n "${SCHEDULE:-}" ]] || ssm_die "Missing SCHEDULE in ${timer_file}"

  if [[ "${TARGET_TYPE}" == "service" ]]; then
    [[ -n "${TARGET_NAME:-}" ]] || ssm_die "Missing TARGET_NAME in ${timer_file}"
    if [[ ! -f "$(ssm_service_config_path "${project_dir}" "${TARGET_NAME}")" ]]; then
      ssm_die "TARGET_NAME references missing service: ${TARGET_NAME}"
    fi
  fi

  if [[ "${TARGET_TYPE}" == "task" ]]; then
    [[ -n "${COMMAND:-}" ]] || ssm_die "Missing COMMAND in ${timer_file}"
  fi

  SSM_TIMER_NAME="${timer_name}"
  SSM_TIMER_SCOPE="${SCOPE:-${DEFAULT_SCOPE:-system}}"
}
