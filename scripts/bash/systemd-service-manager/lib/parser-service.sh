# shellcheck shell=bash

if [[ -n "${SSM_SERVICE_PARSER_LOADED:-}" ]]; then
  return 0
fi
SSM_SERVICE_PARSER_LOADED=1

# 解析单个服务配置，并把项目级默认值补齐到当前上下文。
ssm_parse_service_config() {
  local project_dir="$1"
  local service_name="$2"
  local service_file
  service_file="$(ssm_service_config_path "${project_dir}" "${service_name}")"

  [[ -f "${service_file}" ]] || ssm_die "Missing service config: ${service_file}"

  ssm_load_project_config "${project_dir}"
  ssm_load_key_value_file "${service_file}"
  ssm_load_service_env "${project_dir}" "${service_name}"

  [[ -n "${COMMAND:-}" ]] || ssm_die "Missing COMMAND in ${service_file}"

  SSM_SERVICE_NAME="${service_name}"
  SSM_SERVICE_SCOPE="${SCOPE:-${DEFAULT_SCOPE:-system}}"
}
