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

# 对单块受管磁盘执行统一修复：刷新 unit、确保目录存在、按挂载点重试。
fm_repair_disk() {
  local index="$1"
  local force_mode="$2"
  local mountpoint="${FM_CONFIG_DISK_MOUNTPOINTS[${index}]}"
  local mode="${FM_CONFIG_DISK_MODES[${index}]}"

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
    local device_path
    device_path="$(fm_source_to_device_path "${FM_CONFIG_DISK_SOURCES[${index}]}")"
    if command -v fuser >/dev/null 2>&1 && [[ -e "${device_path}" ]]; then
      fm_run_privileged fuser -k -9 "${device_path}" >/dev/null 2>&1 || true
    fi
  fi

  if fm_run_privileged mount "${mountpoint}" >/dev/null 2>&1; then
    fm_log "info" "Mounted ${mountpoint}"
    return 0
  fi

  fm_log "warn" "Mount retry failed for ${mountpoint}"
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
