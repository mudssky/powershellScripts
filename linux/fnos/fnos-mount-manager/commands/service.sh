# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_SERVICE_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_SERVICE_LOADED=1

# 渲染开机后 reconcile 的 oneshot service，保持启动顺序和入口路径可读。
# 参数：1=要执行的管理器脚本绝对路径。
fm_render_reconcile_service_unit() {
  local entry_path="$1"

  cat <<EOF
[Unit]
Description=FNOS mount manager reconcile after boot
After=local-fs.target trim_main.service
Wants=local-fs.target
ConditionPathExists=${entry_path}

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "${entry_path}" reconcile
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF
}

# 若系统里还残留旧的 force-remount service，则在安装新 service 时一并停用，避免双重干预。
fm_disable_legacy_force_remount_service_if_needed() {
  command -v systemctl >/dev/null 2>&1 || return 0

  local load_state
  load_state="$(systemctl show force-remount-disks.service -p LoadState --value 2>/dev/null || true)"
  [[ -n "${load_state}" && "${load_state}" != "not-found" ]] || return 0

  if systemctl cat force-remount-disks.service 2>/dev/null | grep -q "linux/fnos/remount.sh"; then
    fm_run_privileged systemctl disable --now force-remount-disks.service >/dev/null 2>&1 || true
    fm_log "warn" "Disabled legacy force-remount-disks.service"
  fi
}

# 安装并启用 reconcile 开机 service。默认写入 systemd unit 目录并执行 enable；
# 若输出路径不在 systemd unit 目录下，则只写文件，不自动 enable。
fm_cmd_install_reconcile_service() {
  local output_path
  output_path="$(fm_reconcile_service_path)"
  local start_now="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        output_path="$2"
        shift 2
        ;;
      --start-now)
        start_now="1"
        shift
        ;;
      --help | -h)
        cat <<'EOF'
Usage: fnos-mount-manager install-reconcile-service [--output /path/to/unit.service] [--start-now]

Install and enable a boot-time oneshot service that runs `reconcile` after FNOS mount services settle.
EOF
        return 0
        ;;
      *)
        fm_die "Unknown install-reconcile-service option: $1"
        ;;
    esac
  done

  local entry_path="${FM_MANAGER_ENTRY_PATH}"
  [[ -f "${entry_path}" ]] || fm_die "Manager entry path not found: ${entry_path}"

  local output_dir
  output_dir="$(dirname "${output_path}")"
  fm_run_privileged mkdir -p "${output_dir}"

  local temp_unit
  temp_unit="$(mktemp)"
  fm_render_reconcile_service_unit "${entry_path}" > "${temp_unit}"
  fm_install_file "${temp_unit}" "${output_path}"
  rm -f "${temp_unit}"
  fm_log "info" "Installed reconcile service to ${output_path}"

  local systemd_unit_dir
  systemd_unit_dir="$(fm_systemd_unit_dir)"
  local unit_name
  unit_name="$(basename "${output_path}")"

  if command -v systemctl >/dev/null 2>&1 && [[ "${output_dir}" == "${systemd_unit_dir}" ]]; then
    fm_run_privileged systemctl daemon-reload
    fm_run_privileged systemctl enable "${unit_name}" >/dev/null 2>&1
    fm_log "info" "Enabled ${unit_name}"

    fm_disable_legacy_force_remount_service_if_needed

    if [[ "${start_now}" == "1" ]]; then
      fm_run_privileged systemctl start "${unit_name}" >/dev/null 2>&1
      fm_log "info" "Started ${unit_name}"
    fi
    return 0
  fi

  fm_log "warn" "Skipped systemctl enable because ${output_path} is outside $(fm_systemd_unit_dir)"
}
