#!/usr/bin/env bash
set -Eeuo pipefail

# 开发态直接 source 模块，构建产物则通过 SSM_STANDALONE 避免重复加载。
if [[ -z "${SSM_STANDALONE:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=scripts/bash/systemd-service-manager/common.sh
  source "${SCRIPT_DIR}/common.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/cli.sh
  source "${SCRIPT_DIR}/lib/cli.sh"
fi

# 顶层分发仅保留 help 和错误分支，满足第一轮测试闭环。
ssm_main() {
  ssm_init_environment "${BASH_SOURCE[0]}"

  local command="${1:-help}"
  shift || true

  case "${command}" in
    help | --help | -h | '')
      ssm_show_help
      ;;
    *)
      ssm_die "Unknown command: ${command}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ssm_main "$@"
fi
