# shellcheck shell=bash

if [[ -n "${SSM_PROJECT_LOADED:-}" ]]; then
  return 0
fi
SSM_PROJECT_LOADED=1

# 解析项目目录，允许命令行显式指定，也允许默认落到当前目录。
ssm_find_project_dir() {
  local explicit="${1:-}"
  if [[ -n "${explicit}" ]]; then
    printf '%s\n' "${explicit}"
    return 0
  fi

  printf '%s\n' "${PWD}"
}

# 统一返回项目的 systemd 配置根目录。
ssm_config_root() {
  local project_dir="$1"
  printf '%s/deploy/systemd\n' "${project_dir}"
}

# 返回服务配置文件路径。
ssm_service_config_path() {
  local project_dir="$1"
  local service_name="$2"
  printf '%s/services/%s.conf\n' "$(ssm_config_root "${project_dir}")" "${service_name}"
}

# 返回 timer 配置文件路径。
ssm_timer_config_path() {
  local project_dir="$1"
  local timer_name="$2"
  printf '%s/timers/%s.conf\n' "$(ssm_config_root "${project_dir}")" "${timer_name}"
}

# 统一计算服务 unit 名，后续安装和日志查询复用。
ssm_service_unit_name() {
  local service_name="$1"
  printf '%s-%s.service\n' "${UNIT_PREFIX}" "${service_name}"
}

# 统一计算 timer unit 名。
ssm_timer_unit_name() {
  local timer_name="$1"
  printf '%s-%s.timer\n' "${UNIT_PREFIX}" "${timer_name}"
}

# 统一计算 timer 对应的一次性 task service unit 名。
ssm_timer_task_unit_name() {
  local timer_name="$1"
  printf '%s-task-%s.service\n' "${UNIT_PREFIX}" "${timer_name}"
}
