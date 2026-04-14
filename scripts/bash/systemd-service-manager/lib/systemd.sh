# shellcheck shell=bash

if [[ -n "${SSM_SYSTEMD_LOADED:-}" ]]; then
  return 0
fi
SSM_SYSTEMD_LOADED=1

# 返回 system scope unit 目录，测试可通过环境变量覆写。
ssm_system_unit_dir() {
  printf '%s\n' "${SSM_SYSTEM_UNIT_DIR:-/etc/systemd/system}"
}

# 返回 user scope unit 目录，测试可通过环境变量覆写。
ssm_user_unit_dir() {
  printf '%s\n' "${SSM_USER_UNIT_DIR:-${HOME}/.config/systemd/user}"
}

# 按 scope 选择最终写入目录。
ssm_unit_dir_for_scope() {
  local scope="$1"
  if [[ "${scope}" == "user" ]]; then
    ssm_user_unit_dir
    return 0
  fi

  ssm_system_unit_dir
}

# 按 scope 包装 systemctl 调用，减少命令层分支。
ssm_systemctl() {
  local scope="$1"
  shift
  if [[ "${scope}" == "user" ]]; then
    systemctl --user "$@"
  else
    systemctl "$@"
  fi
}

# 写入新 unit 后统一 reload 对应 scope 的 systemd 配置。
ssm_daemon_reload() {
  local scope="$1"
  ssm_systemctl "${scope}" daemon-reload
}

# 在落盘前用 systemd-analyze 校验 unit 语法。
ssm_verify_unit_file() {
  local unit_file="$1"
  systemd-analyze verify "${unit_file}" >/dev/null 2>&1
}

# 按 scope 包装 journalctl，用于 logs 命令。
ssm_journalctl() {
  local scope="$1"
  shift
  if [[ "${scope}" == "user" ]]; then
    journalctl --user "$@"
  else
    journalctl "$@"
  fi
}

# 判断目标 unit 当前是否已经落盘安装。
ssm_is_unit_installed() {
  local scope="$1"
  local unit_name="$2"
  [[ -f "$(ssm_unit_dir_for_scope "${scope}")/${unit_name}" ]] && printf 'true' || printf 'false'
}

# 把 service/timer 目标解析成 scope 与最终 unit 名，供 lifecycle 命令复用。
ssm_resolve_target_spec() {
  local project_dir="$1"
  local target_kind="$2"
  local target_name="$3"

  if [[ -z "${target_kind}" ]]; then
    ssm_die "Missing target name"
  fi

  case "${target_kind}" in
    service | timer)
      [[ -n "${target_name}" ]] || ssm_die "Missing target name"
      SSM_RESOLVED_TARGET_KIND="${target_kind}"
      SSM_RESOLVED_TARGET_NAME="${target_name}"
      return 0
      ;;
  esac

  if [[ -n "${target_name}" ]]; then
    ssm_die "Unknown target kind: ${target_kind}"
  fi

  local inferred_name="${target_kind}"
  local service_exists="false"
  local timer_exists="false"

  [[ -f "$(ssm_service_config_path "${project_dir}" "${inferred_name}")" ]] && service_exists="true"
  [[ -f "$(ssm_timer_config_path "${project_dir}" "${inferred_name}")" ]] && timer_exists="true"

  case "${service_exists}:${timer_exists}" in
    true:false)
      SSM_RESOLVED_TARGET_KIND="service"
      SSM_RESOLVED_TARGET_NAME="${inferred_name}"
      ;;
    false:true)
      SSM_RESOLVED_TARGET_KIND="timer"
      SSM_RESOLVED_TARGET_NAME="${inferred_name}"
      ;;
    true:true)
      ssm_die "Ambiguous target name: ${inferred_name}. Use 'service ${inferred_name}' or 'timer ${inferred_name}'"
      ;;
    false:false)
      ssm_die "Cannot infer target kind for ${inferred_name}. Use 'service ${inferred_name}' or 'timer ${inferred_name}'"
      ;;
  esac
}

ssm_load_target_context() {
  local target_kind="$1"
  local target_name="$2"
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  ssm_resolve_target_spec "${project_dir}" "${target_kind}" "${target_name}"

  case "${SSM_RESOLVED_TARGET_KIND}" in
    service)
      ssm_parse_service_config "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}"
      SSM_ACTIVE_NAME="${SSM_RESOLVED_TARGET_NAME}"
      SSM_ACTIVE_SCOPE="${SSM_SERVICE_SCOPE}"
      SSM_ACTIVE_UNIT="$(ssm_service_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      ;;
    timer)
      ssm_parse_timer_config "${project_dir}" "${SSM_RESOLVED_TARGET_NAME}"
      SSM_ACTIVE_NAME="${SSM_RESOLVED_TARGET_NAME}"
      SSM_ACTIVE_SCOPE="${SSM_TIMER_SCOPE}"
      SSM_ACTIVE_UNIT="$(ssm_timer_unit_name "${SSM_RESOLVED_TARGET_NAME}")"
      ;;
    *)
      ssm_die "Unknown target kind: ${SSM_RESOLVED_TARGET_KIND}"
      ;;
  esac
}
