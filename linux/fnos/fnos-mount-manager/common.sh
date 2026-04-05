# shellcheck shell=bash

if [[ -n "${FNOS_MOUNT_MANAGER_COMMON_LOADED:-}" ]]; then
  return 0
fi
FNOS_MOUNT_MANAGER_COMMON_LOADED=1

# 输出统一的管理器日志，方便诊断 generate/apply/check/repair 流程。
fm_log() {
  local level="$1"
  shift
  printf '[fnos-mount-manager][%s] %s\n' "${level}" "$*"
}

# 输出错误并终止当前命令。
fm_die() {
  fm_log "error" "$*" >&2
  exit 1
}

# 去掉字符串前后空白，保证 CSV 选项合并结果稳定。
fm_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# 解析当前脚本对应的管理器目录，兼容源码入口、bin 产物和目录内副本。
fm_detect_manager_home() {
  local script_path="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  local candidates=(
    "${script_dir}"
    "${script_dir}/../fnos-mount-manager"
    "${script_dir}/../linux/fnos/fnos-mount-manager"
  )
  local candidate

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}/disks.example.conf" || -f "${candidate}/build.sh" ]]; then
      (cd "${candidate}" && pwd)
      return 0
    fi
  done

  printf '%s\n' "${script_dir}"
}

# 初始化管理器根目录，允许测试通过环境变量覆写。
fm_init_environment() {
  local script_path="$1"

  if [[ -n "${FNOS_MANAGER_HOME:-}" ]]; then
    FM_MANAGER_HOME="${FNOS_MANAGER_HOME}"
  else
    FM_MANAGER_HOME="$(fm_detect_manager_home "${script_path}")"
  fi

  FM_MANAGER_BLOCK_BEGIN="# BEGIN FNOS MOUNT MANAGER"
  FM_MANAGER_BLOCK_END="# END FNOS MOUNT MANAGER"
}

# 返回示例配置文件路径。
fm_example_config_path() {
  printf '%s/disks.example.conf\n' "${FM_MANAGER_HOME}"
}

# 返回本机私有配置文件路径。
fm_local_config_path() {
  printf '%s/disks.local.conf\n' "${FM_MANAGER_HOME}"
}

# 返回示例挂载区块预览文件路径。
fm_example_fstab_path() {
  printf '%s/fstab.example\n' "${FM_MANAGER_HOME}"
}

# 返回本机挂载区块预览文件路径。
fm_local_fstab_path() {
  printf '%s/fstab\n' "${FM_MANAGER_HOME}"
}

# 返回源码入口路径，便于测试对照源码入口与构建产物。
fm_source_entry_path() {
  printf '%s/main.sh\n' "${FM_MANAGER_HOME}"
}

# 合并逗号分隔的挂载选项，避免重复选项污染生成结果。
fm_merge_csv_options() {
  local part
  local item
  local -a merged=()
  local -A seen=()

  for part in "$@"; do
    [[ -n "${part}" ]] || continue
    IFS=',' read -r -a items <<< "${part}"
    for item in "${items[@]}"; do
      item="$(fm_trim "${item}")"
      [[ -n "${item}" ]] || continue
      if [[ -z "${seen["${item}"]+x}" ]]; then
        seen["${item}"]=1
        merged+=("${item}")
      fi
    done
  done

  local IFS=','
  printf '%s' "${merged[*]}"
}

# 把 LABEL:/UUID: 前缀转换成 fstab 可直接使用的 source spec。
fm_source_to_spec() {
  local source="$1"
  case "${source}" in
    LABEL:*)
      printf 'LABEL=%s' "${source#LABEL:}"
      ;;
    UUID:*)
      printf 'UUID=%s' "${source#UUID:}"
      ;;
    *)
      fm_die "Unsupported disk source: ${source}"
      ;;
  esac
}

# 把 LABEL:/UUID: 前缀转换成 /dev/disk/by-* 路径，便于检查设备是否存在。
fm_source_to_device_path() {
  local source="$1"
  local device_root="${FNOS_MANAGER_DEVICE_ROOT:-/dev/disk}"
  case "${source}" in
    LABEL:*)
      printf '%s/by-label/%s' "${device_root}" "${source#LABEL:}"
      ;;
    UUID:*)
      printf '%s/by-uuid/%s' "${device_root}" "${source#UUID:}"
      ;;
    *)
      fm_die "Unsupported disk source: ${source}"
      ;;
  esac
}

# 生成 systemd mount/automount unit 名称，优先复用 systemd-escape 以兼容空格路径。
fm_unit_name_for_path() {
  local path="$1"
  local suffix="$2"
  if command -v systemd-escape >/dev/null 2>&1; then
    systemd-escape --path "${path}" --suffix="${suffix}"
    return 0
  fi

  local escaped="${path#/}"
  escaped="${escaped//\//-}"
  printf '%s.%s\n' "${escaped}" "${suffix}"
}

# 通过 id 检查当前进程是否已经具备 root 权限。
fm_is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

# 在真实系统上优先走 sudo，在测试中允许显式关闭 sudo 以驱动假命令。
fm_run_privileged() {
  if fm_is_root || [[ "${FNOS_MANAGER_TEST_NO_SUDO:-0}" == "1" ]]; then
    "$@"
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    fm_die "sudo is required for privileged operations"
  fi

  sudo "$@"
}

# 在任何入口里安全读取文件内容，文件不存在时返回空字符串。
fm_read_file_or_empty() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    cat "${path}"
    return 0
  fi
  return 0
}

# 从目标 fstab 中提取当前受管区块，便于 check 比较当前系统状态与本地渲染是否一致。
fm_extract_managed_block() {
  local path="$1"
  [[ -f "${path}" ]] || return 0

  awk -v begin="${FM_MANAGER_BLOCK_BEGIN}" -v end="${FM_MANAGER_BLOCK_END}" '
    $0 == begin { in_block = 1 }
    in_block { print }
    $0 == end { in_block = 0 }
  ' "${path}"
}

# 把新的受管区块写回目标 fstab 内容，保留非受管条目不变。
fm_merge_managed_block() {
  local source_file="$1"
  local output_file="$2"
  local block_content="$3"

  if [[ ! -f "${source_file}" ]]; then
    printf '%s\n' "${block_content}" > "${output_file}"
    return 0
  fi

  awk -v begin="${FM_MANAGER_BLOCK_BEGIN}" -v end="${FM_MANAGER_BLOCK_END}" -v block="${block_content}" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    $0 == begin {
      if (!replaced) {
        print block
        replaced = 1
      }
      in_block = 1
      next
    }
    $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
    END {
      if (!replaced) {
        if (NR > 0) {
          print ""
        }
        print block
      }
    }
  ' "${source_file}" > "${output_file}"
}

# 把普通文件安全替换到目标路径。真实系统写 /etc/fstab 时通过提权桥接完成写入。
fm_install_file() {
  local source_file="$1"
  local target_file="$2"
  local target_dir
  target_dir="$(dirname "${target_file}")"

  if [[ -w "${target_dir}" ]]; then
    local temp_target
    temp_target="$(mktemp "${target_file}.tmp.XXXXXX")"
    cp "${source_file}" "${temp_target}"
    chmod 0644 "${temp_target}"
    mv "${temp_target}" "${target_file}"
    return 0
  fi

  local temp_target="${target_file}.fnos-manager.tmp"
  fm_run_privileged sh -c '
    set -eu
    cat "$1" > "$2"
    chmod 0644 "$2"
    mv "$2" "$3"
  ' _ "${source_file}" "${temp_target}" "${target_file}"
}
