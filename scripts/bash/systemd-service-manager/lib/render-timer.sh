# shellcheck shell=bash

if [[ -n "${SSM_RENDER_TIMER_LOADED:-}" ]]; then
  return 0
fi
SSM_RENDER_TIMER_LOADED=1

# 渲染 timer unit，保持 schedule 解析和 managed header 分离。
ssm_render_timer_unit() {
  local source_file="$1"
  local unit_name="$2"
  local schedule_block="$3"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION:-${SSM_TIMER_NAME}}

[Timer]
Unit=${unit_name}
${schedule_block}
Persistent=${PERSISTENT:-true}
${RANDOMIZED_DELAY:+RandomizedDelaySec=${RANDOMIZED_DELAY}}

[Install]
WantedBy=timers.target
EOF
}
