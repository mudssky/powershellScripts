# shellcheck shell=bash

if [[ -n "${SSM_SCHEDULE_LOADED:-}" ]]; then
  return 0
fi
SSM_SCHEDULE_LOADED=1

# 把最小受支持的 cron 形式转换成 systemd OnCalendar，先覆盖当前需要的常见场景。
ssm_convert_cron_to_oncalendar() {
  local schedule="$1"
  local fields=()
  read -r -a fields <<< "${schedule}"

  if [[ "${#fields[@]}" -ne 5 ]]; then
    ssm_die "Unsupported cron syntax: ${schedule}"
  fi

  local minute="${fields[0]}"
  local hour="${fields[1]}"
  local day="${fields[2]}"
  local month="${fields[3]}"
  local weekday="${fields[4]}"

  if [[ "${minute}" =~ [\?LW#] || "${hour}" =~ [\?LW#] || "${day}" =~ [\?LW#] || "${month}" =~ [\?LW#] || "${weekday}" =~ [\?LW#] ]]; then
    ssm_die "Unsupported cron syntax: ${schedule}"
  fi

  if [[ "${minute}" =~ ^[0-9]+$ && "${hour}" =~ ^[0-9]+$ && "${day}" == "*" && "${month}" == "*" && "${weekday}" == "*" ]]; then
    printf 'OnCalendar=*-*-* %02d:%02d:00\n' "${hour}" "${minute}"
    return 0
  fi

  ssm_die "Unsupported cron syntax: ${schedule}"
}

# 统一解析别名和 cron，供后续 timer 渲染复用。
ssm_resolve_schedule() {
  local schedule="$1"

  case "${schedule}" in
    @hourly)
      printf 'OnCalendar=hourly\n'
      ;;
    @daily)
      printf 'OnCalendar=daily\n'
      ;;
    @weekly)
      printf 'OnCalendar=weekly\n'
      ;;
    @monthly)
      printf 'OnCalendar=monthly\n'
      ;;
    @every-5m)
      printf 'OnBootSec=5m\nOnUnitActiveSec=5m\n'
      ;;
    @every-15m)
      printf 'OnBootSec=15m\nOnUnitActiveSec=15m\n'
      ;;
    @every-1h)
      printf 'OnBootSec=1h\nOnUnitActiveSec=1h\n'
      ;;
    *)
      ssm_convert_cron_to_oncalendar "${schedule}"
      ;;
  esac
}
