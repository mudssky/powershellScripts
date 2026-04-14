# shellcheck shell=bash

if [[ -n "${SSM_CLI_LOADED:-}" ]]; then
  return 0
fi
SSM_CLI_LOADED=1

# 输出顶层帮助，先固定命令面，后续再把具体行为逐个接上。
ssm_show_help() {
  cat <<'EOF'
Usage: systemd-service-manager <command> [options]

Commands:
  init
  list
  install
  uninstall
  start
  stop
  restart
  status
  logs
  enable
  disable
  help
EOF
}

# 解析当前阶段公共参数，避免各命令重复消费 --project / --dry-run / --follow。
ssm_parse_common_flags() {
  SSM_CLI_PROJECT_DIR=""
  SSM_CLI_DRY_RUN=0
  SSM_CLI_FOLLOW=0
  SSM_CLI_POSITIONAL_ARGS=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --project)
        [[ "$#" -ge 2 ]] || ssm_die "Missing value for --project"
        SSM_CLI_PROJECT_DIR="$2"
        shift 2
        ;;
      --dry-run)
        SSM_CLI_DRY_RUN=1
        shift
        ;;
      --follow)
        SSM_CLI_FOLLOW=1
        shift
        ;;
      *)
        SSM_CLI_POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done
}
