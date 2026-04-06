# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_ALIAS_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_ALIAS_LOADED=1

# 为已挂在型号路径的磁盘建立业务名 bind mount 别名。
# 参数：1=磁盘索引。
# 返回：0=成功或无需动作；1=同步失败。结果通过 FM_OPERATION_LAST_* 暴露。
fm_alias_disk() {
  local index="$1"
  fm_reset_operation_result
  fm_resolve_disk_runtime_state "${index}"

  case "${FM_DISK_STATE_CLASS}" in
    mounted_expected)
      fm_log "info" "${FM_DISK_STATE_NAME} already uses ${FM_DISK_STATE_MOUNTPOINT}"
      return 0
      ;;
    not_mounted)
      FM_OPERATION_LAST_ACTION="skipped"
      FM_OPERATION_LAST_REASON="disk is not mounted yet"
      fm_log "info" "Skipping ${FM_DISK_STATE_NAME}: ${FM_OPERATION_LAST_REASON}"
      return 0
      ;;
    device_missing)
      FM_OPERATION_LAST_ACTION="skipped"
      FM_OPERATION_LAST_REASON="device is missing at ${FM_DISK_STATE_DEVICE_PATH}"
      fm_log "warn" "Skipping ${FM_DISK_STATE_NAME}: ${FM_OPERATION_LAST_REASON}"
      return 0
      ;;
  esac

  if ! fm_is_exact_mountpoint "${FM_DISK_STATE_MOUNTED_TARGET}"; then
    FM_OPERATION_LAST_ACTION="skipped"
    FM_OPERATION_LAST_REASON="source mountpoint is no longer available at ${FM_DISK_STATE_MOUNTED_TARGET}"
    fm_log "warn" "Skipping ${FM_DISK_STATE_NAME}: ${FM_OPERATION_LAST_REASON}"
    return 0
  fi

  local alias_state
  alias_state="$(
    fm_describe_bind_alias_state \
      "${FM_DISK_STATE_MOUNTED_TARGET}" \
      "${FM_DISK_STATE_MOUNTPOINT}"
  )"

  case "${alias_state}" in
    already_synced)
      fm_log "info" "${FM_DISK_STATE_NAME} already exposes a business alias at ${FM_DISK_STATE_MOUNTPOINT}"
      return 0
      ;;
    occupied)
      FM_OPERATION_LAST_ACTION="failed"
      FM_OPERATION_LAST_REASON="managed mountpoint is occupied by another mount: ${FM_DISK_STATE_MOUNTPOINT}"
      fm_log "error" "${FM_DISK_STATE_NAME} ${FM_OPERATION_LAST_REASON}"
      return 1
      ;;
  esac

  fm_run_privileged mkdir -p "${FM_DISK_STATE_MOUNTPOINT}"

  if fm_run_privileged mount --bind "${FM_DISK_STATE_MOUNTED_TARGET}" "${FM_DISK_STATE_MOUNTPOINT}" >/dev/null 2>&1; then
    FM_OPERATION_LAST_ACTION="alias_synced"
    fm_log "info" "Bound ${FM_DISK_STATE_NAME} from ${FM_DISK_STATE_MOUNTED_TARGET} to ${FM_DISK_STATE_MOUNTPOINT}"
    return 0
  fi

  FM_OPERATION_LAST_ACTION="failed"
  FM_OPERATION_LAST_REASON="bind mount failed from ${FM_DISK_STATE_MOUNTED_TARGET} to ${FM_DISK_STATE_MOUNTPOINT}"
  fm_log "error" "${FM_DISK_STATE_NAME} ${FM_OPERATION_LAST_REASON}"
  return 1
}

# 处理 alias 子命令，只对 mounted_elsewhere 的磁盘建立业务名 bind mount 别名。
fm_cmd_alias() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager alias

Create business-name bind aliases for disks already mounted elsewhere by FNOS.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown alias option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"

  local failures=0
  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    if ! fm_alias_disk "${i}"; then
      failures=$(( failures + 1 ))
    fi
  done

  if (( failures > 0 )); then
    fm_die "Alias sync completed with ${failures} failure(s)"
  fi

  fm_log "info" "Alias sync completed successfully"
}
