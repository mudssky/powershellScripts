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
