# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_REMOUNT_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_REMOUNT_LOADED=1

# 以更主动的方式把磁盘重新挂到受管挂载点：
# 若设备已经被挂到错误路径，会先卸载错误目标，再按我们的挂载点重挂。
fm_remount_disk() {
  local index="$1"
  local name="${FM_CONFIG_DISK_NAMES[${index}]}"
  local source="${FM_CONFIG_DISK_SOURCES[${index}]}"
  local mountpoint="${FM_CONFIG_DISK_MOUNTPOINTS[${index}]}"
  local device_path
  device_path="$(fm_source_to_device_path "${source}")"

  local mounted_target=""
  mounted_target="$(fm_find_mount_target_for_device "${device_path}")"

  if [[ "${mounted_target}" == "${mountpoint}" ]]; then
    fm_log "info" "${name} already mounted at ${mountpoint}"
    return 0
  fi

  fm_run_privileged mkdir -p "${mountpoint}"

  if [[ -n "${mounted_target}" ]]; then
    fm_log "warn" "${name} device is mounted at ${mounted_target}; remounting to ${mountpoint}"

    if ! fm_run_privileged umount "${mounted_target}" >/dev/null 2>&1; then
      # FNOS 相关服务可能仍持有旧路径句柄，显式 remount 时退到 lazy umount。
      fm_run_privileged umount -l "${mounted_target}" >/dev/null 2>&1 || true
    fi

    mounted_target="$(fm_find_mount_target_for_device "${device_path}")"
    if [[ -n "${mounted_target}" ]]; then
      fm_log "warn" "${name} device is still mounted at ${mounted_target}"
      return 1
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local mount_unit
    mount_unit="$(fm_unit_name_for_path "${mountpoint}" mount)"
    fm_run_privileged systemctl reset-failed "${mount_unit}" >/dev/null 2>&1 || true
    fm_run_privileged systemctl stop "${mount_unit}" >/dev/null 2>&1 || true

    local automount_unit
    automount_unit="$(fm_unit_name_for_path "${mountpoint}" automount)"
    fm_run_privileged systemctl reset-failed "${automount_unit}" >/dev/null 2>&1 || true
    fm_run_privileged systemctl stop "${automount_unit}" >/dev/null 2>&1 || true
  fi

  if fm_run_privileged mount "${mountpoint}" >/dev/null 2>&1; then
    fm_log "info" "Remounted ${name} to ${mountpoint}"
    return 0
  fi

  fm_log "warn" "Remount failed for ${name}"
  return 1
}

# 显式接管错误挂载并切回受管命名。
fm_cmd_remount() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager remount

Force managed disks back onto the configured mountpoints.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown remount option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"

  local failures=0
  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    if ! fm_remount_disk "${i}"; then
      failures=$(( failures + 1 ))
    fi
  done

  if (( failures > 0 )); then
    fm_die "Remount completed with ${failures} failure(s)"
  fi

  fm_log "info" "Remount completed successfully"
}
