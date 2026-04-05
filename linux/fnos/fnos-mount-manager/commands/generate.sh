# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_GENERATE_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_GENERATE_LOADED=1

# 把指定配置文件渲染为受控 fstab 区块预览。
fm_generate_scope() {
  local config_path="$1"
  local output_path="$2"
  local source_label="$3"

  fm_load_config "${config_path}"
  fm_render_managed_block "${source_label}" > "${output_path}"
  fm_log "info" "Wrote ${output_path}"
}

# 处理 generate 子命令，默认同时更新 example 和 local 预览。
fm_cmd_generate() {
  local scope="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope)
        scope="$2"
        shift 2
        ;;
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager generate [--scope all|example|local]

Generate managed fstab preview blocks from shell config files.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown generate option: $1"
        ;;
    esac
  done

  case "${scope}" in
    all | example)
      fm_generate_scope "$(fm_example_config_path)" "$(fm_example_fstab_path)" "disks.example.conf"
      ;;
  esac

  case "${scope}" in
    all | local)
      if [[ -f "$(fm_local_config_path)" ]]; then
        fm_generate_scope "$(fm_local_config_path)" "$(fm_local_fstab_path)" "disks.local.conf"
      elif [[ "${scope}" == "local" ]]; then
        fm_die "Local config not found: $(fm_local_config_path)"
      else
        fm_log "warn" "Skipping local generate because disks.local.conf is missing"
      fi
      ;;
  esac
}
