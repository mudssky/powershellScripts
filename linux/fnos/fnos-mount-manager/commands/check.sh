# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_CHECK_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_CHECK_LOADED=1

# 在受管区块不一致时输出统一 diff，方便直接看 preview 和目标文件的差异。
fm_report_managed_block_diff() {
  local expected_block="$1"
  local actual_block="$2"
  local expected_file
  local actual_file
  expected_file="$(mktemp)"
  actual_file="$(mktemp)"

  printf '%s\n' "${expected_block}" > "${expected_file}"
  printf '%s\n' "${actual_block}" > "${actual_file}"

  if command -v diff >/dev/null 2>&1; then
    local diff_output
    diff_output="$(
      diff -u \
        --label "local-preview" \
        --label "target-managed-block" \
        "${expected_file}" \
        "${actual_file}" || true
    )"
    if [[ -n "${diff_output}" ]]; then
      fm_log "error" "Managed block diff:"
      while IFS= read -r line; do
        printf '[fnos-mount-manager][error] %s\n' "${line}" >&2
      done <<< "${diff_output}"
    fi
  else
    fm_log "error" "Managed block diff: diff command not available"
    fm_log "error" "Expected block:"
    printf '%s\n' "${expected_block}" >&2
    fm_log "error" "Actual block:"
    printf '%s\n' "${actual_block}" >&2
  fi

  rm -f "${expected_file}" "${actual_file}"
}

# 检查单个渲染产物是否与当前配置匹配，并把异常累加到错误计数里。
fm_check_rendered_file() {
  local config_path="$1"
  local rendered_path="$2"
  local source_label="$3"
  local -n error_count_ref="$4"

  if [[ ! -f "${rendered_path}" ]]; then
    fm_log "error" "Rendered file is missing: ${rendered_path}"
    error_count_ref=$(( error_count_ref + 1 ))
    return 0
  fi

  local temp_render
  local temp_tmpfiles
  temp_render="$(mktemp)"
  temp_tmpfiles="$(mktemp)"

  fm_generate_scope "${config_path}" "${temp_render}" "${temp_tmpfiles}" "${source_label}"

  if ! cmp -s "${rendered_path}" "${temp_render}"; then
    fm_log "error" "Rendered file is stale: ${rendered_path}"
    error_count_ref=$(( error_count_ref + 1 ))
  fi

  rm -f "${temp_render}" "${temp_tmpfiles}"
}

# 检查已知的 shell 登录补挂载片段，避免把副作用留在非显式命令路径里。
fm_check_legacy_shell_mounts() {
  local mount_root="$1"
  local -n error_count_ref="$2"
  local file
  local legacy_files=(
    "/etc/profile"
    "${HOME}/.profile"
    "${HOME}/.bash_profile"
    "${HOME}/.bashrc"
  )

  for file in "${legacy_files[@]}"; do
    [[ -f "${file}" ]] || continue
    if grep -q "mount -a" "${file}" 2>/dev/null && grep -q "${mount_root}" "${file}" 2>/dev/null; then
      fm_log "error" "Legacy shell mount logic detected in ${file}"
      error_count_ref=$(( error_count_ref + 1 ))
    fi
  done
}

# 检查遗留的 force-remount systemd 服务是否仍指向旧脚本路径。
fm_check_legacy_service() {
  local -n error_count_ref="$1"

  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  local load_state
  load_state="$(systemctl show force-remount-disks.service -p LoadState --value 2>/dev/null || true)"
  [[ -n "${load_state}" && "${load_state}" != "not-found" ]] || return 0

  if systemctl cat force-remount-disks.service 2>/dev/null | grep -q "linux/fnos/remount.sh"; then
    fm_log "error" "Legacy force-remount-disks.service still points to linux/fnos/remount.sh"
    error_count_ref=$(( error_count_ref + 1 ))
  fi
}

# 处理 check 子命令，覆盖配置漂移、设备存在性、目标 fstab 状态和遗留冲突来源。
fm_cmd_check() {
  local target="/etc/fstab"
  local error_count=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        target="$2"
        shift 2
        ;;
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager check [--target /path/to/fstab]

Validate generated previews, device presence, managed block drift, and known legacy conflicts.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown check option: $1"
        ;;
    esac
  done

  fm_check_rendered_file "$(fm_example_config_path)" "$(fm_example_fstab_path)" "disks.example.conf" error_count

  if [[ -f "$(fm_local_config_path)" ]]; then
    fm_check_rendered_file "$(fm_local_config_path)" "$(fm_local_fstab_path)" "disks.local.conf" error_count
    fm_load_config "$(fm_local_config_path)"

    local i
    for (( i = 0; i < ${#FM_CONFIG_DISK_SOURCES[@]}; i += 1 )); do
      fm_resolve_disk_runtime_state "${i}"

      case "${FM_DISK_STATE_CLASS}" in
        device_missing)
          fm_log "error" "Disk source is missing for ${FM_DISK_STATE_NAME}: ${FM_DISK_STATE_DEVICE_PATH}"
          error_count=$(( error_count + 1 ))
          ;;
        mounted_elsewhere)
          fm_log "warn" "Disk is mounted outside the managed path for ${FM_DISK_STATE_NAME}: ${FM_DISK_STATE_MOUNTED_TARGET}"
          ;;
        not_mounted)
          fm_log "warn" "Disk is not mounted for ${FM_DISK_STATE_NAME}: ${FM_DISK_STATE_MOUNTPOINT}"
          ;;
      esac
    done

    if [[ -f "${target}" ]]; then
      local expected_block
      expected_block="$(cat "$(fm_local_fstab_path)")"
      local actual_block
      actual_block="$(fm_extract_managed_block "${target}")"

      if [[ "${expected_block}" != "${actual_block}" ]]; then
        fm_log "error" "Managed block in ${target} does not match the local preview"
        fm_report_managed_block_diff "${expected_block}" "${actual_block}"
        error_count=$(( error_count + 1 ))
      fi
    else
      fm_log "error" "Target fstab does not exist: ${target}"
      error_count=$(( error_count + 1 ))
    fi

    fm_check_legacy_shell_mounts "${FM_CONFIG_MOUNT_ROOT}" error_count
  else
    fm_log "warn" "Local config is missing. Skipping local-only checks."
  fi

  fm_check_legacy_service error_count

  if (( error_count > 0 )); then
    fm_die "Check failed with ${error_count} issue(s)"
  fi

  fm_log "info" "Check passed"
}
