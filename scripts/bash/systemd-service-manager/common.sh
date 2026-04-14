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
