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
  init       初始化当前项目的 deploy/systemd 模板骨架
  list       列出当前项目中声明的 services 与 timers
  install    渲染并安装 service/timer unit 到 systemd
  uninstall  删除当前工具生成的 unit 文件
  start      启动指定 service 或 timer
  stop       停止指定 service 或 timer
  restart    重启指定 service 或 timer
  status     查看指定 service 或 timer 的安装与运行状态
  logs       查看指定 service 或 timer 的 journald 日志
  enable     启用指定 service 或 timer 的自启动
  disable    禁用指定 service 或 timer 的自启动
  help       显示这份帮助信息

Common options:
  --project <path>  指定项目根目录，默认使用当前目录
  --dry-run         只预览将执行的操作，不实际写入 unit
  --follow          配合 logs 使用，持续跟随日志输出

Target syntax:
  <command> <service|timer> <name>   显式指定目标类型
  <command> <name>                   当名字只在 service 或 timer 中命中一个时自动推断类型

Examples:
  systemd-service-manager init
  systemd-service-manager list --project /path/to/app
  systemd-service-manager install service api --project /path/to/app
  systemd-service-manager install api --project /path/to/app
  systemd-service-manager install timer cleanup --project /path/to/app --dry-run
  systemd-service-manager start api --project /path/to/app
  systemd-service-manager logs service api --project /path/to/app --follow
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
