#!/usr/bin/env bash
set -Eeuo pipefail

# 源码入口在开发阶段直接执行，构建产物则通过 FNOS_MANAGER_STANDALONE 避免再次 source 模块。
if [[ -z "${FNOS_MANAGER_STANDALONE:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=linux/fnos/fnos-mount-manager/common.sh
  source "${SCRIPT_DIR}/common.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/config.sh
  source "${SCRIPT_DIR}/config.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/generate.sh
  source "${SCRIPT_DIR}/commands/generate.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/apply.sh
  source "${SCRIPT_DIR}/commands/apply.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/check.sh
  source "${SCRIPT_DIR}/commands/check.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/status.sh
  source "${SCRIPT_DIR}/commands/status.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/service.sh
  source "${SCRIPT_DIR}/commands/service.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/alias.sh
  source "${SCRIPT_DIR}/commands/alias.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/repair.sh
  source "${SCRIPT_DIR}/commands/repair.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/backfill.sh
  source "${SCRIPT_DIR}/commands/backfill.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/reconcile.sh
  source "${SCRIPT_DIR}/commands/reconcile.sh"
  # shellcheck source=linux/fnos/fnos-mount-manager/commands/remount.sh
  source "${SCRIPT_DIR}/commands/remount.sh"
fi

# 输出统一帮助信息，说明配置路径和常用命令。
fm_show_help() {
  cat <<'EOF'
Usage: fnos-mount-manager <command> [options]

Commands:
  generate    Generate managed fstab preview blocks
  apply       Merge the local managed block into a target fstab
  check       Validate config drift and known conflicts
  status      Show current disk and unit status
  install-reconcile-service
              Install and enable the boot-time reconcile oneshot service
  alias       Create business-name bind aliases for FNOS-mounted disks
  backfill    Mount disks that FNOS failed to mount
  reconcile   Run alias sync first, then backfill missing disks
  repair      Attempt a unified mount repair
  remount     Move disks back onto the managed mountpoints
  help        Show this help
EOF
}

# 按子命令分发管理器行为，保持命令面稳定。
fm_main() {
  fm_init_environment "${BASH_SOURCE[0]}"

  local command="${1:-help}"
  shift || true

  case "${command}" in
    generate)
      fm_cmd_generate "$@"
      ;;
    apply)
      fm_cmd_apply "$@"
      ;;
    check)
      fm_cmd_check "$@"
      ;;
    status)
      fm_cmd_status "$@"
      ;;
    install-reconcile-service)
      fm_cmd_install_reconcile_service "$@"
      ;;
    alias)
      fm_cmd_alias "$@"
      ;;
    backfill)
      fm_cmd_backfill "$@"
      ;;
    reconcile)
      fm_cmd_reconcile "$@"
      ;;
    repair)
      fm_cmd_repair "$@"
      ;;
    remount)
      fm_cmd_remount "$@"
      ;;
    help | --help | -h)
      fm_show_help
      ;;
    *)
      fm_die "Unknown command: ${command}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  fm_main "$@"
fi
