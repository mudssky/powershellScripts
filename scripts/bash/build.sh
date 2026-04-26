#!/usr/bin/env bash
set -Eeuo pipefail

# 统一构建 scripts/bash 下的 Bash 工具。
# 支持两种目标：调用子目录 build.sh，或复制单文件 .sh 到 bin。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${REPO_ROOT}/bin"

BASH_BUILD_TARGETS=(
  "build:systemd-service-manager:scripts/bash/systemd-service-manager/build.sh:<managed-by-target-build>"
  "copy:aliyun-oss-put:scripts/bash/aliyun-oss-put.sh:bin/aliyun-oss-put"
)

# 输出统一格式日志。
# 参数：$1 为日志级别，其余参数为日志内容。
# 返回值：无返回值。
bb_log() {
  local level="$1"
  shift
  printf '[bash-build][%s] %s\n' "${level}" "$*"
}

# 输出错误并终止构建流程。
# 参数：所有参数会拼接为错误信息。
# 返回值：不会正常返回，固定以 1 退出。
bb_die() {
  bb_log "error" "$*" >&2
  exit 1
}

# 输出命令行帮助。
# 参数：无。
# 返回值：无返回值。
bb_usage() {
  cat <<'EOF'
Usage: scripts/bash/build.sh [--jobs <n>] [--list] [--only <name>]

Options:
  --jobs <n>     限制并发构建数，必须大于 0
  --list         列出构建目标，不执行构建
  --only <name>  只构建指定目标
  -h, --help     显示帮助
EOF
}

# 获取当前机器可用 CPU 数，用于默认并发数。
# 参数：无。
# 返回值：向 stdout 输出正整数；无法探测时输出 1。
bb_cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
    return 0
  fi
  printf '1\n'
}

# 判断值是否为正整数。
# 参数：$1 为待检查的字符串。
# 返回值：是正整数返回 0，否则返回 1。
bb_is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

# 解析构建入口参数，并写入 BB_* 全局状态。
# 参数：构建入口收到的原始命令行参数。
# 返回值：解析成功返回 0；参数非法时直接退出。
bb_parse_args() {
  BB_LIST=0
  BB_ONLY=""
  BB_JOBS=""
  BB_JOBS_SOURCE="cpu"
  BB_RAW_ARGS="$*"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --jobs)
        [[ "$#" -ge 2 ]] || bb_die "Missing value for --jobs; args=${BB_RAW_ARGS}"
        BB_JOBS="$2"
        BB_JOBS_SOURCE="--jobs"
        shift 2
        ;;
      --list)
        BB_LIST=1
        shift
        ;;
      --only)
        [[ "$#" -ge 2 ]] || bb_die "Missing value for --only; args=${BB_RAW_ARGS}"
        BB_ONLY="$2"
        shift 2
        ;;
      -h | --help)
        bb_usage
        exit 0
        ;;
      *)
        bb_die "Unknown argument: $1; args=${BB_RAW_ARGS}"
        ;;
    esac
  done

  if [[ -z "${BB_JOBS}" && -n "${BASH_BUILD_JOBS:-}" ]]; then
    BB_JOBS="${BASH_BUILD_JOBS}"
    BB_JOBS_SOURCE="BASH_BUILD_JOBS"
  fi
}

# 根据 --only 过滤目标清单，并写入 BB_SELECTED_TARGETS。
# 参数：无，依赖 BASH_BUILD_TARGETS 与 BB_ONLY。
# 返回值：匹配成功返回 0；目标不存在时直接退出。
bb_select_targets() {
  BB_SELECTED_TARGETS=()
  local target type name source output matched=0
  for target in "${BASH_BUILD_TARGETS[@]}"; do
    IFS=':' read -r type name source output <<<"${target}"
    if [[ -n "${BB_ONLY}" && "${name}" != "${BB_ONLY}" ]]; then
      continue
    fi
    matched=1
    BB_SELECTED_TARGETS+=("${target}")
  done

  if [[ -n "${BB_ONLY}" && "${matched}" -eq 0 ]]; then
    bb_die "Unknown target: ${BB_ONLY}"
  fi
}

# 计算本次构建的有效并发数。
# 参数：$1 为选中的任务数量。
# 返回值：写入 BB_EFFECTIVE_JOBS，成功返回 0；并发值非法时直接退出。
bb_resolve_jobs() {
  local task_count="$1"
  if [[ "${task_count}" -le 0 ]]; then
    BB_EFFECTIVE_JOBS=1
    return 0
  fi

  if [[ -z "${BB_JOBS}" ]]; then
    BB_JOBS="$(bb_cpu_count)"
    BB_JOBS_SOURCE="cpu"
  fi

  bb_is_positive_integer "${BB_JOBS}" || bb_die "Invalid jobs value: ${BB_JOBS}; args=${BB_RAW_ARGS}"
  BB_EFFECTIVE_JOBS="${BB_JOBS}"
  if [[ "${BB_EFFECTIVE_JOBS}" -gt "${task_count}" ]]; then
    BB_EFFECTIVE_JOBS="${task_count}"
  fi
  [[ "${BB_EFFECTIVE_JOBS}" -ge 1 ]] || BB_EFFECTIVE_JOBS=1
}

# 输出当前选中的构建目标元数据。
# 参数：无，依赖 BB_SELECTED_TARGETS。
# 返回值：无返回值。
bb_list_targets() {
  local target type name source output
  for target in "${BB_SELECTED_TARGETS[@]}"; do
    IFS=':' read -r type name source output <<<"${target}"
    printf 'name=%s\n' "${name}"
    printf 'type=%s\n' "${type}"
    printf 'source=%s\n' "${source}"
    printf 'output=%s\n' "${output}"
    printf '\n'
  done
}

# 执行单个构建目标，并把目标内部输出写入独立日志文件。
# 参数：$1 为目标描述串，$2 为日志文件路径。
# 返回值：目标成功返回 0；失败返回目标退出码或 1。
bb_run_target() {
  local target="$1"
  local log_file="$2"
  local type name source output source_path output_path start_time end_time duration
  IFS=':' read -r type name source output <<<"${target}"
  source_path="${REPO_ROOT}/${source}"
  output_path="${REPO_ROOT}/${output}"
  start_time="$(date +%s)"

  printf 'START %s type=%s source=%s\n' "${name}" "${type}" "${source}"

  local exit_code=0
  set +e
  case "${type}" in
    build)
      printf 'ACTION %s run build.sh\n' "${name}"
      if [[ ! -f "${source_path}" ]]; then
        bb_log "error" "Missing build script: ${source}" >"${log_file}" 2>&1
        exit_code=1
      else
        bash "${source_path}" >"${log_file}" 2>&1
        exit_code=$?
      fi
      ;;
    copy)
      printf 'ACTION %s copy source -> %s\n' "${name}" "${output}"
      if [[ ! -f "${source_path}" ]]; then
        bb_log "error" "Missing shell script: ${source}" >"${log_file}" 2>&1
        exit_code=1
      elif [[ "${source_path}" != *.sh ]]; then
        bb_log "error" "Copy target must be .sh: ${source}" >"${log_file}" 2>&1
        exit_code=1
      else
        {
          mkdir -p "$(dirname "${output_path}")"
          cp "${source_path}" "${output_path}"
          chmod 0755 "${output_path}"
        } >"${log_file}" 2>&1
        exit_code=$?
      fi
      ;;
    *)
      bb_log "error" "Unknown target type: ${type}" >"${log_file}" 2>&1
      exit_code=1
      ;;
  esac
  set -e

  end_time="$(date +%s)"
  duration=$((end_time - start_time))
  if [[ "${exit_code}" -eq 0 ]]; then
    printf 'DONE %s exit=0 duration=%ss output=%s log=%s\n' "${name}" "${duration}" "${output}" "${log_file}"
  else
    printf 'FAIL %s exit=%s duration=%ss log=%s\n' "${name}" "${exit_code}" "${duration}" "${log_file}"
  fi
  return "${exit_code}"
}

# 构建入口主流程：解析参数、选择目标、调度执行并输出摘要。
# 参数：构建入口收到的原始命令行参数。
# 返回值：全部目标成功返回 0；任一目标失败返回 1。
bb_main() {
  bb_parse_args "$@"
  bb_select_targets
  bb_resolve_jobs "${#BB_SELECTED_TARGETS[@]}"

  local log_dir
  log_dir="$(mktemp -d)"
  bb_log "info" "args=${BB_RAW_ARGS:-<none>}"
  bb_log "info" "repo=${REPO_ROOT}"
  bb_log "info" "bin=${BIN_DIR}"
  bb_log "info" "logs=${log_dir}"
  bb_log "info" "list=$([[ ${BB_LIST} -eq 1 ]] && printf true || printf false) only=${BB_ONLY:-all}"
  bb_log "info" "jobs=${BB_EFFECTIVE_JOBS} source=${BB_JOBS_SOURCE}"
  bb_log "info" "targets=${#BB_SELECTED_TARGETS[@]}"

  if [[ "${BB_LIST}" -eq 1 ]]; then
    bb_list_targets
    return 0
  fi

  local success=0 failed=0 skipped=0 target name log_file result_file
  local -a pids=() result_files=()

  for target in "${BB_SELECTED_TARGETS[@]}"; do
    IFS=':' read -r _ name _ _ <<<"${target}"
    log_file="${log_dir}/${name}.log"
    result_file="${log_dir}/${name}.result"
    (bb_run_target "${target}" "${log_file}" >"${result_file}") &
    pids+=("$!")
    result_files+=("${result_file}")

    # 到达并发上限时等待最早提交的任务，既保持输出稳定，也限制资源占用。
    if [[ "${#pids[@]}" -ge "${BB_EFFECTIVE_JOBS}" ]]; then
      if wait "${pids[0]}"; then success=$((success + 1)); else failed=$((failed + 1)); fi
      cat "${result_files[0]}"
      pids=("${pids[@]:1}")
      result_files=("${result_files[@]:1}")
    fi
  done

  local index=0
  while [[ "${index}" -lt "${#pids[@]}" ]]; do
    if wait "${pids[${index}]}"; then success=$((success + 1)); else failed=$((failed + 1)); fi
    cat "${result_files[${index}]}"
    index=$((index + 1))
  done

  printf 'SUMMARY total=%s success=%s failed=%s skipped=%s\n' "${#BB_SELECTED_TARGETS[@]}" "${success}" "${failed}" "${skipped}"
  [[ "${failed}" -eq 0 ]]
}

bb_main "$@"
