# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_STATUS_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_STATUS_LOADED=1

# 输出单块受管磁盘的配置与当前系统状态，供人工排障使用。
fm_print_disk_status() {
  local index="$1"
  fm_resolve_disk_runtime_state "${index}"

  printf '%s\n' "${FM_DISK_STATE_NAME}"
  printf '  source: %s\n' "${FM_DISK_STATE_SOURCE}"
  printf '  mountpoint: %s\n' "${FM_DISK_STATE_MOUNTPOINT}"
  printf '  mode: %s\n' "${FM_DISK_STATE_MODE}"
  printf '  device_path: %s\n' "${FM_DISK_STATE_DEVICE_PATH}"
  printf '  device_exists: %s\n' "${FM_DISK_STATE_DEVICE_EXISTS}"
  printf '  classification: %s\n' "${FM_DISK_STATE_CLASS}"
  printf '  mounted: %s\n' "$([[ "${FM_DISK_STATE_CLASS}" == "mounted_expected" ]] && printf 'yes' || printf 'no')"
  if [[ "${FM_DISK_STATE_CLASS}" == "mounted_elsewhere" ]]; then
    printf '  mounted_elsewhere: %s\n' "${FM_DISK_STATE_MOUNTED_TARGET}"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local mount_unit
    mount_unit="$(fm_unit_name_for_path "${FM_DISK_STATE_MOUNTPOINT}" mount)"
    printf '  mount_unit: %s\n' "${mount_unit}"
    printf '  mount_state: %s\n' "$(systemctl show "${mount_unit}" -p ActiveState --value 2>/dev/null || printf 'unknown')"

    if [[ "${FM_DISK_STATE_MODE}" == "automount" ]]; then
      local automount_unit
      automount_unit="$(fm_unit_name_for_path "${FM_DISK_STATE_MOUNTPOINT}" automount)"
      printf '  automount_unit: %s\n' "${automount_unit}"
      printf '  automount_state: %s\n' "$(systemctl show "${automount_unit}" -p ActiveState --value 2>/dev/null || printf 'unknown')"
    fi
  fi
}

# 处理 status 子命令，展示当前机器对受管磁盘的解析结果。
fm_cmd_status() {
  local config_path
  if [[ -f "$(fm_local_config_path)" ]]; then
    config_path="$(fm_local_config_path)"
  else
    config_path="$(fm_example_config_path)"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager status

Show the current status of managed disks, mountpoints, and systemd units.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown status option: $1"
        ;;
    esac
  done

  fm_load_config "${config_path}"

  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    fm_print_disk_status "${i}"
  done
}
