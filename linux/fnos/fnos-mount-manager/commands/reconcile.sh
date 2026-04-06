# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_RECONCILE_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_RECONCILE_LOADED=1

# 输出 reconcile 汇总，既给人看阶段结果，也给测试提供稳定断言面。
# 参数：1=磁盘名数组名；2=动作数组名；3=失败原因数组名。
# 返回：通过 FM_RECONCILE_FAILED_COUNT 暴露失败计数。
fm_print_reconcile_summary() {
  local -n names_ref="$1"
  local -n actions_ref="$2"
  local -n reasons_ref="$3"
  local unchanged=0
  local alias_synced=0
  local backfilled=0
  local failed=0
  local i

  for (( i = 0; i < ${#actions_ref[@]}; i += 1 )); do
    case "${actions_ref[${i}]}" in
      unchanged)
        unchanged=$(( unchanged + 1 ))
        ;;
      alias_synced)
        alias_synced=$(( alias_synced + 1 ))
        ;;
      backfilled)
        backfilled=$(( backfilled + 1 ))
        ;;
      failed)
        failed=$(( failed + 1 ))
        ;;
    esac
  done

  FM_RECONCILE_FAILED_COUNT="${failed}"

  printf 'Reconcile summary:\n'
  printf '  unchanged: %s\n' "${unchanged}"
  printf '  alias_synced: %s\n' "${alias_synced}"
  printf '  backfilled: %s\n' "${backfilled}"
  printf '  failed: %s\n' "${failed}"

  for (( i = 0; i < ${#names_ref[@]}; i += 1 )); do
    printf '  %s: %s' "${names_ref[${i}]}" "${actions_ref[${i}]}"
    if [[ "${actions_ref[${i}]}" == "failed" && -n "${reasons_ref[${i}]}" ]]; then
      printf ' (%s)' "${reasons_ref[${i}]}"
    fi
    printf '\n'
  done
}

# 处理 reconcile 子命令，按“先 alias、再 backfill”的顺序输出统一纠偏结果。
fm_cmd_reconcile() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager reconcile

Synchronize business-name aliases first, then backfill disks that are still not mounted.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown reconcile option: $1"
        ;;
    esac
  done

  [[ -f "$(fm_local_config_path)" ]] || fm_die "Local config not found: $(fm_local_config_path)"
  fm_load_config "$(fm_local_config_path)"

  local -a disk_names=()
  local -a disk_actions=()
  local -a disk_reasons=()
  local i

  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    disk_names[${i}]="${FM_CONFIG_DISK_NAMES[${i}]}"
    disk_actions[${i}]="unchanged"
    disk_reasons[${i}]=""

    fm_resolve_disk_runtime_state "${i}"
    if [[ "${FM_DISK_STATE_CLASS}" == "device_missing" ]]; then
      disk_actions[${i}]="failed"
      disk_reasons[${i}]="device is missing at ${FM_DISK_STATE_DEVICE_PATH}"
    fi
  done

  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    [[ "${disk_actions[${i}]}" == "failed" ]] && continue

    fm_resolve_disk_runtime_state "${i}"
    [[ "${FM_DISK_STATE_CLASS}" == "mounted_elsewhere" ]] || continue

    if fm_alias_disk "${i}"; then
      if [[ "${FM_OPERATION_LAST_ACTION}" == "alias_synced" ]]; then
        disk_actions[${i}]="alias_synced"
      fi
      continue
    fi

    disk_actions[${i}]="failed"
    disk_reasons[${i}]="${FM_OPERATION_LAST_REASON}"
  done

  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    [[ "${disk_actions[${i}]}" == "failed" ]] && continue

    fm_resolve_disk_runtime_state "${i}"
    [[ "${FM_DISK_STATE_CLASS}" == "not_mounted" ]] || continue

    if fm_backfill_disk "${i}"; then
      if [[ "${FM_OPERATION_LAST_ACTION}" == "backfilled" ]]; then
        disk_actions[${i}]="backfilled"
      fi
      continue
    fi

    disk_actions[${i}]="failed"
    disk_reasons[${i}]="${FM_OPERATION_LAST_REASON}"
  done

  fm_print_reconcile_summary disk_names disk_actions disk_reasons

  if (( FM_RECONCILE_FAILED_COUNT > 0 )); then
    fm_die "Reconcile completed with ${FM_RECONCILE_FAILED_COUNT} failure(s)"
  fi

  fm_log "info" "Reconcile completed successfully"
}
