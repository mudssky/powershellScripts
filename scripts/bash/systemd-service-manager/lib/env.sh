# shellcheck shell=bash

if [[ -n "${SSM_ENV_LOADED:-}" ]]; then
  return 0
fi
SSM_ENV_LOADED=1

# 去除首尾空白，确保配置解析一致。
ssm_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# 以保守方式去掉完整包裹的引号，不执行任何 shell 代码。
ssm_normalize_value() {
  local raw_value
  raw_value="$(ssm_trim "$1")"

  case "${raw_value}" in
    \"*\")
      raw_value="${raw_value#\"}"
      raw_value="${raw_value%\"}"
      ;;
    \'*\')
      raw_value="${raw_value#\'}"
      raw_value="${raw_value%\'}"
      ;;
  esac

  printf '%s' "${raw_value}"
}

# 读取受控 KEY=VALUE 文件，只接受显式键值，不执行 source。
ssm_load_key_value_file() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0

  local line=""
  local key=""
  local value=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(ssm_trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ "${line}" != *=* ]]; then
      ssm_die "Invalid key-value line in ${file_path}: ${line}"
    fi

    key="$(ssm_trim "${line%%=*}")"
    value="$(ssm_normalize_value "${line#*=}")"

    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      ssm_die "Invalid config key in ${file_path}: ${key}"
    fi

    printf -v "${key}" '%s' "${value}"
  done < "${file_path}"
}

# 加载项目级默认配置与环境变量，后加载文件覆盖前加载文件。
ssm_load_project_config() {
  local project_dir="$1"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  ssm_load_key_value_file "${config_root}/project.conf"
  ssm_load_key_value_file "${config_root}/project.env"
  ssm_load_key_value_file "${config_root}/project.env.local"

  SSM_PROJECT_NAME="${PROJECT_NAME:-}"
  UNIT_PREFIX="${UNIT_PREFIX:-${PROJECT_NAME:-project}}"
  DEFAULT_SCOPE="${DEFAULT_SCOPE:-system}"
}

# 加载服务级环境变量，覆盖项目默认值。
ssm_load_service_env() {
  local project_dir="$1"
  local service_name="$2"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  ssm_load_key_value_file "${config_root}/services/${service_name}.env"
  ssm_load_key_value_file "${config_root}/services/${service_name}.env.local"
}

# 加载 timer 级环境变量，覆盖项目默认值。
ssm_load_timer_env() {
  local project_dir="$1"
  local timer_name="$2"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  ssm_load_key_value_file "${config_root}/timers/${timer_name}.env"
  ssm_load_key_value_file "${config_root}/timers/${timer_name}.env.local"
}
