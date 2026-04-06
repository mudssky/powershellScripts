# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_BACKFILL_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_BACKFILL_LOADED=1

# 为未被 FNOS 成功挂上的磁盘执行单独补挂，不干扰已健康或已挂错路径的盘。
# 参数：1=磁盘索引。
# 返回：0=成功或无需动作；1=补挂失败。结果通过 FM_OPERATION_LAST_* 暴露。
fm_backfill_disk() {
  local index="$1"
  fm_reset_operation_result
  fm_resolve_disk_runtime_state "${index}"

  case "${FM_DISK_STATE_CLASS}" in
    mounted_expected)
      fm_log "info" "${FM_DISK_STATE_NAME} already uses ${FM_DISK_STATE_MOUNTPOINT}"
      return 0
      ;;
    mounted_elsewhere)
      FM_OPERATION_LAST_ACTION="skipped"
      FM_OPERATION_LAST_REASON="disk is already mounted at ${FM_DISK_STATE_MOUNTED_TARGET}"
      fm_log "info" "Skipping ${FM_DISK_STATE_NAME}: ${FM_OPERATION_LAST_REASON}"
      return 0
      ;;
    device_missing)
      FM_OPERATION_LAST_ACTION="failed"
      FM_OPERATION_LAST_REASON="device is missing at ${FM_DISK_STATE_DEVICE_PATH}"
      fm_log "error" "${FM_DISK_STATE_NAME} ${FM_OPERATION_LAST_REASON}"
      return 1
      ;;
  esac

  if ! fm_mount_disk_to_configured_target "${index}" "0"; then
    FM_OPERATION_LAST_ACTION="failed"
    FM_OPERATION_LAST_REASON="mount retry failed for ${FM_DISK_STATE_MOUNTPOINT}"
    fm_log "error" "${FM_DISK_STATE_NAME} ${FM_OPERATION_LAST_REASON}"
    return 1
  fi

  fm_resolve_disk_runtime_state "${index}"
  if [[ "${FM_DISK_STATE_CLASS}" == "mounted_expected" ]]; then
    FM_OPERATION_LAST_ACTION="backfilled"
    fm_log "info" "Backfilled ${FM_DISK_STATE_NAME} to ${FM_DISK_STATE_MOUNTPOINT}"
    return 0
  fi

  FM_OPERATION_LAST_ACTION="failed"
  FM_OPERATION_LAST_REASON="mount command succeeded but final state is ${FM_DISK_STATE_CLASS}"
  fm_log "error" "${FM_DISK_STATE_NAME} ${FM_OPERATION_LAST_REASON}"
  return 1
}

# 处理 backfill 子命令，只对 not_mounted 的磁盘尝试补挂。
fm_cmd_backfill() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager backfill

Mount not-yet-mounted disks onto their configured business mountpoints.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown backfill option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"

  local failures=0
  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    if ! fm_backfill_disk "${i}"; then
      failures=$(( failures + 1 ))
    fi
  done

  if (( failures > 0 )); then
    fm_die "Backfill completed with ${failures} failure(s)"
  fi

  fm_log "info" "Backfill completed successfully"
}
