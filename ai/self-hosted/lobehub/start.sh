#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 脚本名称: start.sh
# 脚本描述: LobeChat Docker Compose 管理脚本，支持外部依赖模式和内置回滚模式
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERNAL_COMPOSE_FILE="docker-compose.with-internal-db.yml"
INTERNAL_ENV_FILE=".env.with-internal-services"

ACTION="${1:-start}"
SERVICE="lobe"
MODE="external"

if [ "${2:-}" != "" ]; then
  case "$2" in
    external|internal)
      MODE="$2"
      ;;
    *)
      SERVICE="$2"
      ;;
  esac
fi

if [ "${3:-}" != "" ]; then
  MODE="$3"
fi

print_usage() {
  printf "%s\n" "用法: ./start.sh <start|restart|update|status|logs|stop|down> [service] [external|internal]"
  printf "%s\n" "示例:"
  printf "%s\n" "  ./start.sh start"
  printf "%s\n" "  ./start.sh start lobe"
  printf "%s\n" "  ./start.sh status internal"
  printf "%s\n" "  ./start.sh logs searxng"
  printf "%s\n" ""
  printf "%s\n" "默认 service: lobe"
  printf "%s\n" "默认 mode: external"
  printf "%s\n" ""
  printf "%s\n" "模式说明:"
  printf "%s\n" "  external - 使用 docker-compose.yml，依赖宿主机上的 PostgreSQL / Redis / RustFS"
  printf "%s\n" "  internal - 使用 docker-compose.with-internal-db.yml + .env.with-internal-services"
  printf "%s\n" ""
  printf "%s\n" "命令说明:"
  printf "%s\n" "  start   - 启动服务 (默认后台运行)"
  printf "%s\n" "  restart - 重启服务"
  printf "%s\n" "  update  - 拉取最新镜像并重启服务 (支持 'all' 更新所有服务)"
  printf "%s\n" "  status  - 查看服务运行状态"
  printf "%s\n" "  logs    - 查看服务日志 (默认跟随输出)"
  printf "%s\n" "  stop    - 停止服务"
  printf "%s\n" "  down    - 停止并移除当前模式下的所有容器"
}

run_compose() {
  if [ "$MODE" = "internal" ]; then
    docker compose -f "$INTERNAL_COMPOSE_FILE" --env-file "$INTERNAL_ENV_FILE" "$@"
  else
    docker compose "$@"
  fi
}

cd "$SCRIPT_DIR"

case "$MODE" in
  external|internal)
    ;;
  *)
    echo "错误: 未知模式 '$MODE'"
    print_usage
    exit 1
    ;;
esac

case "$ACTION" in
  start)
    echo "正在启动服务: $SERVICE (mode=$MODE) ..."
    run_compose up -d --no-attach "$SERVICE"
    ;;
  restart)
    echo "正在重启服务: $SERVICE (mode=$MODE) ..."
    run_compose restart "$SERVICE"
    ;;
  update)
    if [ "$SERVICE" = "all" ]; then
      echo "正在更新所有服务镜像 (mode=$MODE) ..."
      run_compose pull
      echo "正在重新部署所有服务 (mode=$MODE) ..."
      run_compose up -d --remove-orphans
    else
      echo "正在更新服务镜像及其相关依赖: $SERVICE (mode=$MODE) ..."
      run_compose pull --include-deps "$SERVICE"
      echo "正在重新部署服务及其相关依赖: $SERVICE (mode=$MODE) ..."
      run_compose up -d --always-recreate-deps --no-attach "$SERVICE"
    fi
    ;;
  status)
    run_compose ps
    ;;
  logs)
    echo "正在查看日志: $SERVICE (mode=$MODE, Ctrl+C 退出)..."
    run_compose logs -f --tail=200 "$SERVICE"
    ;;
  stop)
    echo "正在停止服务: $SERVICE (mode=$MODE) ..."
    run_compose stop "$SERVICE"
    ;;
  down)
    echo "正在移除当前模式下的所有服务 (mode=$MODE) ..."
    run_compose down
    ;;
  help|-h|--help)
    print_usage
    ;;
  *)
    echo "错误: 未知命令 '$ACTION'"
    print_usage
    exit 1
    ;;
esac
