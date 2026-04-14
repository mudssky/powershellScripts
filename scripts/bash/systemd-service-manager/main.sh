#!/usr/bin/env bash
set -Eeuo pipefail

# 开发态直接 source 模块，构建产物则通过 SSM_STANDALONE 避免重复加载。
if [[ -z "${SSM_STANDALONE:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=scripts/bash/systemd-service-manager/common.sh
  source "${SCRIPT_DIR}/common.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/cli.sh
  source "${SCRIPT_DIR}/lib/cli.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/project.sh
  source "${SCRIPT_DIR}/lib/project.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/env.sh
  source "${SCRIPT_DIR}/lib/env.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/parser-service.sh
  source "${SCRIPT_DIR}/lib/parser-service.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/parser-timer.sh
  source "${SCRIPT_DIR}/lib/parser-timer.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/schedule.sh
  source "${SCRIPT_DIR}/lib/schedule.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/render-service.sh
  source "${SCRIPT_DIR}/lib/render-service.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/render-timer.sh
  source "${SCRIPT_DIR}/lib/render-timer.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/systemd.sh
  source "${SCRIPT_DIR}/lib/systemd.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/validate.sh
  source "${SCRIPT_DIR}/lib/validate.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/init.sh
  source "${SCRIPT_DIR}/commands/init.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/list.sh
  source "${SCRIPT_DIR}/commands/list.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/install.sh
  source "${SCRIPT_DIR}/commands/install.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/start.sh
  source "${SCRIPT_DIR}/commands/start.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/stop.sh
  source "${SCRIPT_DIR}/commands/stop.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/restart.sh
  source "${SCRIPT_DIR}/commands/restart.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/status.sh
  source "${SCRIPT_DIR}/commands/status.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/logs.sh
  source "${SCRIPT_DIR}/commands/logs.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/enable.sh
  source "${SCRIPT_DIR}/commands/enable.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/commands/disable.sh
  source "${SCRIPT_DIR}/commands/disable.sh"
fi

# 顶层分发仅保留 help 和错误分支，满足第一轮测试闭环。
ssm_main() {
  ssm_init_environment "${BASH_SOURCE[0]}"

  local command="${1:-help}"
  shift || true

  ssm_parse_common_flags "$@"
  set -- "${SSM_CLI_POSITIONAL_ARGS[@]}"

  case "${command}" in
    help | --help | -h | '')
      ssm_show_help
      ;;
    init)
      ssm_cmd_init "$@"
      ;;
    list)
      ssm_cmd_list "$@"
      ;;
    install)
      ssm_cmd_install "$@"
      ;;
    start)
      ssm_cmd_start "$@"
      ;;
    stop)
      ssm_cmd_stop "$@"
      ;;
    restart)
      ssm_cmd_restart "$@"
      ;;
    status)
      ssm_cmd_status "$@"
      ;;
    logs)
      ssm_cmd_logs "$@"
      ;;
    enable)
      ssm_cmd_enable "$@"
      ;;
    disable)
      ssm_cmd_disable "$@"
      ;;
    debug-schedule)
      [[ -n "${1:-}" ]] || ssm_die "Missing schedule expression"
      ssm_resolve_schedule "$1"
      ;;
    *)
      ssm_die "Unknown command: ${command}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ssm_main "$@"
fi
