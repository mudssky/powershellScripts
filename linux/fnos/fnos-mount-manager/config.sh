# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_CONFIG_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_CONFIG_LOADED=1

# 重置配置 DSL 的内存状态，确保每次加载配置文件前都从干净状态开始。
fm_config_reset() {
  FM_CONFIG_MOUNT_ROOT="/vol00"
  FM_CONFIG_DEFAULT_FS="ntfs"
  FM_CONFIG_DEFAULT_MODE="automount"
  FM_CONFIG_DEFAULT_OPTIONS=""
  FM_CONFIG_DEFAULT_DEVICE_TIMEOUT="60"
  FM_CONFIG_DISK_NAMES=()
  FM_CONFIG_DISK_SOURCES=()
  FM_CONFIG_DISK_MODES=()
  FM_CONFIG_DISK_FSTYPES=()
  FM_CONFIG_DISK_OPTIONS=()
  FM_CONFIG_DISK_TIMEOUTS=()
  FM_CONFIG_DISK_MOUNTPOINTS=()
}

# 配置默认挂载根目录。
mount_root() {
  FM_CONFIG_MOUNT_ROOT="$1"
}

# 配置默认文件系统类型。
default_fs() {
  FM_CONFIG_DEFAULT_FS="$1"
}

# 配置默认挂载模式。
default_mode() {
  FM_CONFIG_DEFAULT_MODE="$1"
}

# 配置默认挂载选项。
default_options() {
  FM_CONFIG_DEFAULT_OPTIONS="$1"
}

# 配置默认设备等待超时秒数。
default_device_timeout() {
  FM_CONFIG_DEFAULT_DEVICE_TIMEOUT="$1"
}

# 验证挂载模式是否属于当前脚本支持的枚举值。
fm_validate_mode() {
  local mode="$1"
  case "${mode}" in
    automount | eager)
      return 0
      ;;
    *)
      fm_die "Unsupported mount mode: ${mode}"
      ;;
  esac
}

# 验证磁盘来源是否为 LABEL:/UUID: 这两种受控格式。
fm_validate_source() {
  local source="$1"
  case "${source}" in
    LABEL:* | UUID:*)
      return 0
      ;;
    *)
      fm_die "Disk source must start with LABEL: or UUID:: ${source}"
      ;;
  esac
}

# 注册一块受管磁盘，支持针对模式、挂载点、选项和超时做按盘覆盖。
disk() {
  local name="${1:-}"
  local source="${2:-}"
  shift 2 || true

  [[ -n "${name}" ]] || fm_die "Disk name is required"
  [[ -n "${source}" ]] || fm_die "Disk source is required for disk ${name}"

  fm_validate_source "${source}"

  local mode="${FM_CONFIG_DEFAULT_MODE}"
  local fs="${FM_CONFIG_DEFAULT_FS}"
  local options=""
  local device_timeout="${FM_CONFIG_DEFAULT_DEVICE_TIMEOUT}"
  local mountpoint="${FM_CONFIG_MOUNT_ROOT}/${name}"
  local arg

  for arg in "$@"; do
    case "${arg}" in
      mode=*)
        mode="${arg#mode=}"
        ;;
      fs=*)
        fs="${arg#fs=}"
        ;;
      options=*)
        options="${arg#options=}"
        ;;
      mount=*)
        mountpoint="${arg#mount=}"
        if [[ "${mountpoint}" != /* ]]; then
          mountpoint="${FM_CONFIG_MOUNT_ROOT}/${mountpoint}"
        fi
        ;;
      device_timeout=*)
        device_timeout="${arg#device_timeout=}"
        ;;
      *)
        fm_die "Unsupported disk option for ${name}: ${arg}"
        ;;
    esac
  done

  fm_validate_mode "${mode}"

  FM_CONFIG_DISK_NAMES+=("${name}")
  FM_CONFIG_DISK_SOURCES+=("${source}")
  FM_CONFIG_DISK_MODES+=("${mode}")
  FM_CONFIG_DISK_FSTYPES+=("${fs}")
  FM_CONFIG_DISK_OPTIONS+=("${options}")
  FM_CONFIG_DISK_TIMEOUTS+=("${device_timeout}")
  FM_CONFIG_DISK_MOUNTPOINTS+=("${mountpoint}")
}

# 加载 shell 配置文件并验证磁盘定义是否完整且不重复。
fm_load_config() {
  local config_path="$1"
  [[ -f "${config_path}" ]] || fm_die "Config file not found: ${config_path}"

  fm_config_reset
  # 配置 DSL 就是管理器的用户接口，因此这里直接 source，并在事后做结构校验。
  # shellcheck disable=SC1090
  source "${config_path}"

  local disk_count="${#FM_CONFIG_DISK_NAMES[@]}"
  (( disk_count > 0 )) || fm_die "Config file does not define any disks: ${config_path}"

  local -A seen=()
  local i
  for (( i = 0; i < disk_count; i += 1 )); do
    local name="${FM_CONFIG_DISK_NAMES[${i}]}"
    if [[ -n "${seen["${name}"]+x}" ]]; then
      fm_die "Duplicate disk name detected: ${name}"
    fi
    seen["${name}"]=1
  done
}

# 返回给定索引磁盘的最终挂载选项，统一附加 automount/eager 模式所需的 systemd 选项。
fm_disk_rendered_options() {
  local index="$1"
  local base_options="${FM_CONFIG_DEFAULT_OPTIONS}"
  local disk_options="${FM_CONFIG_DISK_OPTIONS[${index}]}"
  local mode="${FM_CONFIG_DISK_MODES[${index}]}"
  local device_timeout="${FM_CONFIG_DISK_TIMEOUTS[${index}]}"
  local mode_options=""

  if [[ -n "${device_timeout}" ]]; then
    mode_options="$(fm_merge_csv_options "${mode_options}" "x-systemd.device-timeout=${device_timeout}")"
  fi

  if [[ "${mode}" == "automount" ]]; then
    mode_options="$(fm_merge_csv_options "${mode_options}" "x-systemd.automount")"
  fi

  fm_merge_csv_options "${base_options}" "${disk_options}" "${mode_options}"
}

# 把当前内存中的磁盘配置渲染成受控 fstab 区块。
fm_render_managed_block() {
  local source_label="$1"
  local i

  printf '%s\n' "${FM_MANAGER_BLOCK_BEGIN}"
  printf '# Managed by fnos-mount-manager\n'
  printf '# Source: %s\n' "${source_label}"

  for (( i = 0; i < ${#FM_CONFIG_DISK_NAMES[@]}; i += 1 )); do
    local source_spec
    source_spec="$(fm_source_to_spec "${FM_CONFIG_DISK_SOURCES[${i}]}")"
    printf '%s %s %s %s 0 0\n' \
      "${source_spec}" \
      "${FM_CONFIG_DISK_MOUNTPOINTS[${i}]}" \
      "${FM_CONFIG_DISK_FSTYPES[${i}]}" \
      "$(fm_disk_rendered_options "${i}")"
  done

  printf '%s\n' "${FM_MANAGER_BLOCK_END}"
}
