# shellcheck shell=bash

if [[ -n "${SSM_RENDER_SERVICE_LOADED:-}" ]]; then
  return 0
fi
SSM_RENDER_SERVICE_LOADED=1

# 渲染常驻 service unit，保持最小字段集合和统一 managed header。
ssm_render_service_unit() {
  local source_file="$1"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION:-${SSM_SERVICE_NAME}}
${AFTER:+After=${AFTER}}
${WANTS:+Wants=${WANTS}}

[Service]
Type=simple
WorkingDirectory=${WORKDIR:-${DEFAULT_WORKDIR:-/tmp}}
ExecStart=${COMMAND}
${USER:+User=${USER}}
${GROUP:+Group=${GROUP}}
Restart=${RESTART:-on-failure}
RestartSec=${RESTART_SEC:-5s}

[Install]
WantedBy=${WANTED_BY:-multi-user.target}
EOF
}

# 渲染 timer 触发的一次性 task/service wrapper unit。
ssm_render_task_service_unit() {
  local source_file="$1"
  local exec_command="$2"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION:-${SSM_TIMER_NAME}}

[Service]
Type=oneshot
WorkingDirectory=${WORKDIR:-${DEFAULT_WORKDIR:-/tmp}}
ExecStart=${exec_command}
${USER:+User=${USER}}
${GROUP:+Group=${GROUP}}
EOF
}
