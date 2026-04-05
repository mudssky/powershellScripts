# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_STATUS_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_STATUS_LOADED=1

# 输出单块受管磁盘的配置与当前系统状态，供人工排障使用。
fm_print_disk_status() {
  local index="$1"
  local name="${FM_CONFIG_DISK_NAMES[${index}]}"
  local source="${FM_CONFIG_DISK_SOURCES[${index}]}"
  local mountpoint="${FM_CONFIG_DISK_MOUNTPOINTS[${index}]}"
  local mode="${FM_CONFIG_DISK_MODES[${index}]}"
  local device_path
  device_path="$(fm_source_to_device_path "${source}")"
  local mounted_target=""
  mounted_target="$(fm_find_mount_target_for_device "${device_path}" || true)"

  printf '%s\n' "${name}"
  printf '  source: %s\n' "${source}"
  printf '  mountpoint: %s\n' "${mountpoint}"
  printf '  mode: %s\n' "${mode}"
  printf '  device_path: %s\n' "${device_path}"
  printf '  device_exists: %s\n' "$([[ -e "${device_path}" ]] && printf 'yes' || printf 'no')"
  printf '  mounted: %s\n' "$([[ -n "${mounted_target}" && "${mounted_target}" == "${mountpoint}" ]] && printf 'yes' || printf 'no')"
  if [[ -n "${mounted_target}" && "${mounted_target}" != "${mountpoint}" ]]; then
    printf '  mounted_elsewhere: %s\n' "${mounted_target}"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local mount_unit
    mount_unit="$(fm_unit_name_for_path "${mountpoint}" mount)"
    printf '  mount_unit: %s\n' "${mount_unit}"
    printf '  mount_state: %s\n' "$(systemctl show "${mount_unit}" -p ActiveState --value 2>/dev/null || printf 'unknown')"

    if [[ "${mode}" == "automount" ]]; then
      local automount_unit
      automount_unit="$(fm_unit_name_for_path "${mountpoint}" automount)"
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
