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

# 读取当前 unit 的 installed/enabled/active 摘要，供状态展示和成功提示复用。
ssm_collect_unit_summary() {
  local scope="$1"
  local unit_name="$2"

  SSM_SUMMARY_INSTALLED="$(ssm_is_unit_installed "${scope}" "${unit_name}")"
  SSM_SUMMARY_ENABLED="$(ssm_systemctl "${scope}" is-enabled "${unit_name}" 2>/dev/null || true)"
  SSM_SUMMARY_ACTIVE="$(ssm_systemctl "${scope}" is-active "${unit_name}" 2>/dev/null || true)"

  [[ -n "${SSM_SUMMARY_ENABLED}" ]] || SSM_SUMMARY_ENABLED="unknown"
  [[ -n "${SSM_SUMMARY_ACTIVE}" ]] || SSM_SUMMARY_ACTIVE="unknown"
}

# 输出统一状态摘要，并附加人类可读提示。
ssm_print_unit_summary() {
  local name="$1"
  local scope="$2"
  local unit_name="$3"

  ssm_collect_unit_summary "${scope}" "${unit_name}"

  printf 'name=%s\n' "${name}"
  printf 'unit=%s\n' "${unit_name}"
  printf 'scope=%s\n' "${scope}"
  printf 'installed=%s\n' "${SSM_SUMMARY_INSTALLED}"
  printf 'enabled=%s\n' "${SSM_SUMMARY_ENABLED}"
  printf 'active=%s\n' "${SSM_SUMMARY_ACTIVE}"

  if [[ "${SSM_SUMMARY_ENABLED}" == "disabled" && "${SSM_SUMMARY_ACTIVE}" != "inactive" ]]; then
    printf 'note=unit 已启动但未启用开机自启\n'
  fi

  if [[ "${SSM_SUMMARY_ACTIVE}" == "activating" ]]; then
    printf 'note=unit 正在启动中\n'
  fi
}

# 判断当前命令是否需要在非 root 下自动提权。
ssm_should_auto_elevate() {
  local command="$1"

  case "${command}" in
    install | start | stop | restart | enable | disable)
      ;;
    *)
      return 1
      ;;
  esac

  [[ "${SSM_CLI_DRY_RUN:-0}" == "1" ]] && return 1
  [[ "${SSM_ELEVATED_BY_SCRIPT:-0}" == "1" ]] && return 1
  ssm_is_root && return 1

  local target_kind="${SSM_CLI_POSITIONAL_ARGS[0]:-}"
  local target_name="${SSM_CLI_POSITIONAL_ARGS[1]:-}"
  ssm_load_target_context "${target_kind}" "${target_name}"
  [[ "${SSM_ACTIVE_SCOPE}" == "system" ]]
}

# 以脚本绝对路径重新执行自身，并交给 sudo 完成提权。
ssm_reexec_with_sudo() {
  local source_path="$1"
  local argv0="$2"
  shift 2
  local script_path
  script_path="$(ssm_resolve_executable_path "${source_path}" "${argv0}")"

  command -v sudo >/dev/null 2>&1 || ssm_die "sudo is required for system-scope write operations"
  exec env SSM_ELEVATED_BY_SCRIPT=1 sudo -- bash "${script_path}" "$@"
}
