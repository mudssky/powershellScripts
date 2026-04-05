# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_REPAIR_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_REPAIR_LOADED=1

# 检查旧的 force-remount service 是否仍指向已废弃脚本。
fm_legacy_service_uses_old_script() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl cat force-remount-disks.service 2>/dev/null | grep -q "linux/fnos/remount.sh"
}

# 为一次显式挂载重试准备目录和 systemd 状态。
# 参数：1=挂载点；2=挂载模式；3=设备路径；4=是否 force。
# 返回：0=准备完成；非零=准备失败。
fm_prepare_configured_mount_retry() {
  local mountpoint="$1"
  local mode="$2"
  local device_path="$3"
  local force_mode="$4"

  fm_run_privileged mkdir -p "${mountpoint}"

  if command -v systemctl >/dev/null 2>&1; then
    local mount_unit
    mount_unit="$(fm_unit_name_for_path "${mountpoint}" mount)"
    fm_run_privileged systemctl reset-failed "${mount_unit}" >/dev/null 2>&1 || true

    if [[ "${mode}" == "automount" ]]; then
      local automount_unit
      automount_unit="$(fm_unit_name_for_path "${mountpoint}" automount)"
      fm_run_privileged systemctl reset-failed "${automount_unit}" >/dev/null 2>&1 || true

      if [[ "${force_mode}" == "1" ]]; then
        fm_run_privileged systemctl stop "${automount_unit}" >/dev/null 2>&1 || true
      fi
      fm_run_privileged systemctl start "${automount_unit}" >/dev/null 2>&1 || true
    fi

    if [[ "${force_mode}" == "1" ]]; then
      fm_run_privileged systemctl stop "${mount_unit}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${force_mode}" == "1" ]]; then
    if command -v fuser >/dev/null 2>&1 && [[ -e "${device_path}" ]]; then
      fm_run_privileged fuser -k -9 "${device_path}" >/dev/null 2>&1 || true
    fi
  fi

  return 0
}

# 按受管挂载点执行一次显式 mount 重试，供 repair/backfill 共用。
# 参数：1=磁盘索引；2=是否 force。
# 返回：0=mount 命令成功；1=mount 命令失败。
fm_mount_disk_to_configured_target() {
  local index="$1"
  local force_mode="$2"
  fm_resolve_disk_runtime_state "${index}"

  fm_prepare_configured_mount_retry \
    "${FM_DISK_STATE_MOUNTPOINT}" \
    "${FM_DISK_STATE_MODE}" \
    "${FM_DISK_STATE_DEVICE_PATH}" \
    "${force_mode}"

  if fm_run_privileged mount "${FM_DISK_STATE_MOUNTPOINT}" >/dev/null 2>&1; then
    fm_log "info" "Mounted ${FM_DISK_STATE_MOUNTPOINT}"
    return 0
  fi

  fm_log "warn" "Mount retry failed for ${FM_DISK_STATE_MOUNTPOINT}"
  return 1
}

# 对单块受管磁盘执行统一修复：刷新 unit、确保目录存在、按挂载点重试。
# 参数：1=磁盘索引；2=是否 force。
# 返回：0=修复成功或无需动作；1=修复失败。
fm_repair_disk() {
  local index="$1"
  local force_mode="$2"
  fm_resolve_disk_runtime_state "${index}"

  case "${FM_DISK_STATE_CLASS}" in
    mounted_expected)
      fm_log "info" "${FM_DISK_STATE_NAME} already mounted at ${FM_DISK_STATE_MOUNTPOINT}"
      return 0
      ;;
    mounted_elsewhere)
      fm_log "warn" "${FM_DISK_STATE_NAME} device is already mounted at ${FM_DISK_STATE_MOUNTED_TARGET}"
      return 1
      ;;
    device_missing)
      fm_log "warn" "${FM_DISK_STATE_NAME} device is missing at ${FM_DISK_STATE_DEVICE_PATH}"
      return 1
      ;;
  esac

  if fm_mount_disk_to_configured_target "${index}" "${force_mode}"; then
    return 0
  fi

  return 1
}

# 处理 repair 子命令，默认走安全恢复路径，只有 --force 才执行破坏性步骤。
fm_cmd_repair() {
  local force_mode="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force_mode="1"
        shift
        ;;
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager repair [--force]

Repair managed mountpoints. Default mode is non-destructive.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown repair option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"

  if command -v systemctl >/dev/null 2>&1; then
    fm_run_privileged systemctl daemon-reload
    if [[ "${force_mode}" == "1" ]] && fm_legacy_service_uses_old_script; then
      fm_run_privileged systemctl disable --now force-remount-disks.service >/dev/null 2>&1 || true
      fm_log "warn" "Disabled legacy force-remount-disks.service"
    fi
  fi

  local failures=0
  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    if ! fm_repair_disk "${i}" "${force_mode}"; then
      failures=$(( failures + 1 ))
    fi
  done

  if (( failures > 0 )); then
    fm_die "Repair completed with ${failures} mount failure(s)"
  fi

  fm_log "info" "Repair completed successfully"
}
