# shellcheck shell=bash

if [[ -n "${SSM_COMMON_LOADED:-}" ]]; then
  return 0
fi
SSM_COMMON_LOADED=1

# 输出统一日志前缀，方便调试源码入口和构建产物。
ssm_log() {
  local level="$1"
  shift
  printf '[systemd-service-manager][%s] %s\n' "${level}" "$*"
}

# 统一错误出口，避免各命令自己拼接错误格式。
ssm_die() {
  ssm_log "error" "$*" >&2
  exit 1
}

# 根据入口脚本位置定位 manager 源码目录，兼容源码入口与单文件产物。
ssm_detect_manager_home() {
  local script_path="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  local candidates=(
    "${script_dir}"
    "${script_dir}/systemd-service-manager"
    "${script_dir}/scripts/bash/systemd-service-manager"
  )
  local candidate

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}/build.sh" || -d "${candidate}/tests" ]]; then
      (
        cd "${candidate}" &&
          pwd
      )
      return 0
    fi
  done

  printf '%s\n' "${script_dir}"
}

# 初始化运行时共享目录信息，给后续命令复用。
ssm_init_environment() {
  local script_path="$1"
  SSM_MANAGER_HOME="$(ssm_detect_manager_home "${script_path}")"
}

# 返回当前有效 uid；测试可通过环境变量覆写，避免依赖宿主用户身份。
ssm_current_euid() {
  if [[ -n "${SSM_TEST_EUID:-}" ]]; then
    printf '%s\n' "${SSM_TEST_EUID}"
    return 0
  fi

  id -u
}

# 判断当前是否已经具备 root 权限。
ssm_is_root() {
  [[ "$(ssm_current_euid)" == "0" ]]
}

# 把脚本入口解析成绝对路径，兼容 PATH 调用和显式路径调用。
ssm_resolve_executable_path() {
  local source_path="$1"
  local argv0="$2"
  local candidate="${source_path}"

  if [[ "${candidate}" != */* ]]; then
    candidate="${argv0}"
  fi

  if [[ "${candidate}" != */* ]]; then
    candidate="$(command -v "${candidate}" 2>/dev/null || true)"
  fi

  [[ -n "${candidate}" ]] || ssm_die "Unable to resolve executable path for elevation"

  if command -v realpath >/dev/null 2>&1; then
    realpath "${candidate}" 2>/dev/null && return 0
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "${candidate}" 2>/dev/null && return 0
  fi

  if [[ "${candidate}" == /* ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s/%s\n' "${PWD}" "${candidate}"
}
