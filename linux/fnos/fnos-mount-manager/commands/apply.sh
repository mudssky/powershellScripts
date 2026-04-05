# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_APPLY_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_APPLY_LOADED=1

# 检查本机预览文件是否与当前 local 配置一致，防止 apply 直接跳过 generate。
fm_assert_local_preview_is_fresh() {
  local fstab_preview_path
  local tmpfiles_preview_path
  fstab_preview_path="$(fm_local_fstab_path)"
  tmpfiles_preview_path="$(fm_local_tmpfiles_path)"
  [[ -f "${fstab_preview_path}" ]] || fm_die "Local preview is missing. Run generate first."
  [[ -f "${tmpfiles_preview_path}" ]] || fm_die "Local tmpfiles preview is missing. Run generate first."

  local temp_fstab_render
  local temp_tmpfiles_render
  temp_fstab_render="$(mktemp)"
  temp_tmpfiles_render="$(mktemp)"

  fm_generate_scope \
    "$(fm_local_config_path)" \
    "${temp_fstab_render}" \
    "${temp_tmpfiles_render}" \
    "disks.local.conf"

  if ! cmp -s "${fstab_preview_path}" "${temp_fstab_render}"; then
    rm -f "${temp_fstab_render}" "${temp_tmpfiles_render}"
    fm_die "Local preview is stale. Run generate before apply."
  fi

  if ! cmp -s "${tmpfiles_preview_path}" "${temp_tmpfiles_render}"; then
    rm -f "${temp_fstab_render}" "${temp_tmpfiles_render}"
    fm_die "Local tmpfiles preview is stale. Run generate before apply."
  fi

  rm -f "${temp_fstab_render}" "${temp_tmpfiles_render}"
}

# 确保所有受管挂载点目录存在，避免 mount 或 automount 首次触发时落到不存在路径。
fm_prepare_mountpoints() {
  local i
  for (( i = 0; i < ${#FM_CONFIG_DISK_MOUNTPOINTS[@]}; i += 1 )); do
    fm_run_privileged mkdir -p "${FM_CONFIG_DISK_MOUNTPOINTS[${i}]}"
  done
}

# 处理 apply 子命令，支持通过 --target 把受控区块写到其他 fstab 文件。
fm_cmd_apply() {
  local target="/etc/fstab"
  local tmpfiles_target="/etc/tmpfiles.d/fnos-mount-manager.conf"
  local install_tmpfiles="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        target="$2"
        shift 2
        ;;
      --tmpfiles-target)
        tmpfiles_target="$2"
        install_tmpfiles="1"
        shift 2
        ;;
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager apply [--target /path/to/fstab] [--tmpfiles-target /path/to/tmpfiles.conf]

Merge the generated managed block into the target fstab file and optionally install tmpfiles rules.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown apply option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"
  fm_assert_local_preview_is_fresh

  local temp_output
  temp_output="$(mktemp)"

  if [[ -f "${target}" ]]; then
    fm_merge_managed_block "${target}" "${temp_output}" "$(cat "$(fm_local_fstab_path)")"
  else
    cat "$(fm_local_fstab_path)" > "${temp_output}"
  fi

  if [[ "${target}" == "/etc/fstab" ]]; then
    fm_prepare_mountpoints
    install_tmpfiles="1"
  fi

  fm_install_file "${temp_output}" "${target}"
  rm -f "${temp_output}"
  fm_log "info" "Applied managed block to ${target}"

  if [[ "${install_tmpfiles}" == "1" ]]; then
    fm_install_file "$(fm_local_tmpfiles_path)" "${tmpfiles_target}"
    fm_log "info" "Applied tmpfiles rules to ${tmpfiles_target}"
  fi

  if [[ "${target}" == "/etc/fstab" ]] && command -v systemctl >/dev/null 2>&1; then
    fm_run_privileged systemctl daemon-reload
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
      fm_run_privileged systemd-tmpfiles --create "${tmpfiles_target}"
    fi
  fi
}
