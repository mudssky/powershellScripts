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

# 从指定 key=value 文件中读取某个 key 的最后一个值，用于解析与环境变量同名的配置键。
ssm_read_key_value_from_file() {
  local file_path="$1"
  local target_key="$2"
  [[ -f "${file_path}" ]] || return 0

  local line=""
  local key=""
  local value=""
  local found=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(ssm_trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" == *=* ]] || continue

    key="$(ssm_trim "${line%%=*}")"
    value="$(ssm_normalize_value "${line#*=}")"
    if [[ "${key}" == "${target_key}" ]]; then
      found="${value}"
    fi
  done < "${file_path}"

  printf '%s' "${found}"
}

# 清空当前待渲染的环境变量集合。
ssm_reset_env_entries() {
  SSM_ENV_KEYS=()
  SSM_ENV_VALUES=()
}

# 合并同名环境变量，后出现的值覆盖先前的值。
ssm_upsert_env_entry() {
  local key="$1"
  local value="$2"
  local index=0

  while [[ "${index}" -lt "${#SSM_ENV_KEYS[@]}" ]]; do
    if [[ "${SSM_ENV_KEYS[${index}]}" == "${key}" ]]; then
      SSM_ENV_VALUES[${index}]="${value}"
      return 0
    fi
    index=$((index + 1))
  done

  SSM_ENV_KEYS+=("${key}")
  SSM_ENV_VALUES+=("${value}")
}

# 把 key=value 文件合并到待渲染的环境变量集合里。
ssm_merge_env_file_into_entries() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0

  local line=""
  local key=""
  local value=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(ssm_trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" == *=* ]] || ssm_die "Invalid key-value line in ${file_path}: ${line}"

    key="$(ssm_trim "${line%%=*}")"
    value="$(ssm_normalize_value "${line#*=}")"

    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      ssm_die "Invalid config key in ${file_path}: ${key}"
    fi

    ssm_upsert_env_entry "${key}" "${value}"
  done < "${file_path}"
}

# 按项目级 -> 项目 local -> service 级 -> service local 顺序收集 service 环境变量。
ssm_collect_env_entries_for_service() {
  local project_dir="$1"
  local service_name="$2"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  ssm_reset_env_entries
  ssm_merge_env_file_into_entries "${config_root}/project.env"
  ssm_merge_env_file_into_entries "${config_root}/project.env.local"
  ssm_merge_env_file_into_entries "${config_root}/services/${service_name}.env"
  ssm_merge_env_file_into_entries "${config_root}/services/${service_name}.env.local"
}

# 按项目级 -> 项目 local -> timer 级 -> timer local 顺序收集 timer 环境变量。
ssm_collect_env_entries_for_timer() {
  local project_dir="$1"
  local timer_name="$2"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  ssm_reset_env_entries
  ssm_merge_env_file_into_entries "${config_root}/project.env"
  ssm_merge_env_file_into_entries "${config_root}/project.env.local"
  ssm_merge_env_file_into_entries "${config_root}/timers/${timer_name}.env"
  ssm_merge_env_file_into_entries "${config_root}/timers/${timer_name}.env.local"
}

# 从当前已收集的环境变量集合里读取某个 key 的值，便于调试输出。
ssm_get_env_entry_value() {
  local target_key="$1"
  local index=0

  while [[ "${index}" -lt "${#SSM_ENV_KEYS[@]}" ]]; do
    if [[ "${SSM_ENV_KEYS[${index}]}" == "${target_key}" ]]; then
      printf '%s' "${SSM_ENV_VALUES[${index}]}"
      return 0
    fi
    index=$((index + 1))
  done
}

# 对 Environment= 值做最小转义，避免双引号和反斜杠破坏 unit 语法。
ssm_escape_unit_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

# 把当前环境变量集合渲染成 systemd Environment= 行。
ssm_render_environment_lines() {
  local index=0
  while [[ "${index}" -lt "${#SSM_ENV_KEYS[@]}" ]]; do
    printf 'Environment="%s=%s"\n' \
      "${SSM_ENV_KEYS[${index}]}" \
      "$(ssm_escape_unit_env_value "${SSM_ENV_VALUES[${index}]}")"
    index=$((index + 1))
  done
}
