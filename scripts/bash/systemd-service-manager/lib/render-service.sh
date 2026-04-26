# shellcheck shell=bash

if [[ -n "${SSM_RENDER_SERVICE_LOADED:-}" ]]; then
  return 0
fi
SSM_RENDER_SERVICE_LOADED=1

# 生成安全的单引号 shell 参数，用于嵌入固定的 retry wrapper 脚本。
# 参数：$1 为待引用字符串。
# 返回值：向 stdout 输出可交给 shell 解析的单引号参数。
ssm_shell_single_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

# 生成 systemd ExecStart 中的双引号参数，保留命令里的单引号片段。
# 参数：$1 为待引用字符串。
# 返回值：向 stdout 输出 systemd 命令行可解析的双引号参数。
ssm_systemd_double_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  printf '"%s"' "${value}"
}

# 渲染 timer task 的 ExecStart；未配置 retry 时保持原始命令。
# 参数：$1 为原始 ExecStart 命令。
# 返回值：向 stdout 输出 ExecStart 及可选 Environment 行。
ssm_render_task_exec_start() {
  local exec_command="$1"
  local retry_attempts="${SSM_TIMER_RETRY_ATTEMPTS:-1}"
  local retry_delay_sec="${SSM_TIMER_RETRY_DELAY_SEC:-5}"

  if [[ "${retry_attempts}" -le 1 ]]; then
    printf 'ExecStart=%s\n' "${exec_command}"
    return 0
  fi

  local retry_script
  retry_script='attempt=1; while true; do eval "$1"; code=$?; if [ "$code" -eq 0 ] || [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then exit "$code"; fi; sleep "$RETRY_DELAY_SEC"; attempt=$((attempt + 1)); done'

  printf 'Environment="RETRY_ATTEMPTS=%s"\n' "${retry_attempts}"
  printf 'Environment="RETRY_DELAY_SEC=%s"\n' "${retry_delay_sec}"
  printf 'ExecStart=/usr/bin/env bash -lc %s bash %s\n' \
    "$(ssm_shell_single_quote "${retry_script}")" \
    "$(ssm_systemd_double_quote "${exec_command}")"
}

# 渲染常驻 service unit，保持最小字段集合和统一 managed header。
ssm_render_service_unit() {
  local source_file="$1"
  local env_block="${2:-}"
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
${env_block}
ExecStart=${COMMAND}
${SSM_SERVICE_RUN_USER:+User=${SSM_SERVICE_RUN_USER}}
${SSM_SERVICE_RUN_GROUP:+Group=${SSM_SERVICE_RUN_GROUP}}
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
  local env_block="${3:-}"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION:-${SSM_TIMER_NAME}}

[Service]
Type=oneshot
WorkingDirectory=${WORKDIR:-${DEFAULT_WORKDIR:-/tmp}}
${env_block}
$(ssm_render_task_exec_start "${exec_command}")
${SSM_TIMER_RUN_USER:+User=${SSM_TIMER_RUN_USER}}
${SSM_TIMER_RUN_GROUP:+Group=${SSM_TIMER_RUN_GROUP}}
EOF
}
