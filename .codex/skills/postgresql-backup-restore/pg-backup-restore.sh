#!/usr/bin/env bash
set -euo pipefail

# 功能：输出统一错误消息并以非零状态退出。
# 入参：$1 为错误文本。
# 返回：向 stderr 输出消息并退出。
die() {
  printf '[pg-backup-restore][error] %s\n' "$1" >&2
  exit 1
}

# 功能：输出普通信息消息。
# 入参：$1 为提示文本。
# 返回：向 stdout 输出消息。
log_info() {
  printf '[pg-backup-restore][info] %s\n' "$1"
}

# 功能：输出脚本帮助。
# 入参：无。
# 返回：向 stdout 输出可执行命令、参数和示例。
print_usage() {
  cat <<'EOF'
Usage:
  pg-backup-restore.sh help
  pg-backup-restore.sh install-hint [--platform linux|macos|windows] [--manager auto|apt|dnf|yum|apk|brew|winget|choco]
  pg-backup-restore.sh backup [options]
  pg-backup-restore.sh restore [options]

Common options:
  --host HOST
  --port PORT
  --user USER
  --password PASSWORD
  --database DATABASE
  --dry-run

Backup options:
  --output PATH
  --format custom|plain|directory|tar
  --jobs N
  --schema NAME
  --table NAME
  --exclude-table NAME
  --schema-only
  --data-only

Restore options:
  --input PATH
  --clean
  --if-exists
  --no-owner
  --no-privileges
  --schema NAME
  --table NAME
  --jobs N

Examples:
  bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh install-hint --platform linux --manager apt
  PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh backup --host 127.0.0.1 --user postgres --database app --output ./app.dump --dry-run
  PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh restore --host 127.0.0.1 --user postgres --database app_restore --input ./app.dump --clean --dry-run
EOF
}

# 功能：根据当前 shell 环境推断平台名称。
# 入参：无。
# 返回：输出 `linux`、`macos`、`windows` 或 `unknown`。
detect_platform() {
  local uname_output
  uname_output="$(uname -s 2>/dev/null || printf 'unknown')"

  case "${uname_output}" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'macos\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# 功能：把命令数组渲染成可复制的 dry-run 输出。
# 入参：任意数量的命令片段。
# 返回：使用 shell-safe 形式输出拼好的命令。
print_command_preview() {
  local part
  for part in "$@"; do
    printf '%q ' "$part"
  done
  printf '\n'
}

# 功能：检测命令是否存在。
# 入参：$1 为命令名。
# 返回：命令存在时返回 0，否则返回 1。
has_command() {
  command -v "$1" >/dev/null 2>&1
}

# 功能：输出 PostgreSQL CLI 安装命令提示。
# 入参：可选 `--platform` 与 `--manager`。
# 返回：向 stdout 输出推荐安装命令。
install_hint() {
  local platform
  local manager="auto"
  platform="$(detect_platform)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform)
        [[ $# -ge 2 ]] || die '--platform 缺少值。'
        platform="$2"
        shift 2
        ;;
      --manager)
        [[ $# -ge 2 ]] || die '--manager 缺少值。'
        manager="$2"
        shift 2
        ;;
      *)
        die "install-hint 不支持的参数: $1"
        ;;
    esac
  done

  case "$platform" in
    linux)
      if [[ "$manager" == "auto" ]]; then
        manager="apt"
      fi
      case "$manager" in
        apt)
          printf 'sudo apt-get update\nsudo apt-get install -y postgresql-client\n'
          ;;
        dnf)
          printf 'sudo dnf install -y postgresql\n'
          ;;
        yum)
          printf 'sudo yum install -y postgresql\n'
          ;;
        apk)
          printf 'sudo apk add postgresql-client\n'
          ;;
        *)
          die "Linux 不支持的包管理器: $manager"
          ;;
      esac
      ;;
    macos)
      [[ "$manager" == "auto" ]] && manager="brew"
      [[ "$manager" == "brew" ]] || die "macOS 不支持的包管理器: $manager"
      printf 'brew install libpq\nbrew link --force libpq\n'
      ;;
    windows)
      [[ "$manager" == "auto" ]] && manager="winget"
      case "$manager" in
        winget)
          printf 'winget install --id PostgreSQL.PostgreSQL --source winget\n'
          ;;
        choco)
          printf 'choco install postgresql --yes\n'
          ;;
        *)
          die "Windows 不支持的包管理器: $manager"
          ;;
      esac
      ;;
    *)
      die "无法识别的平台: $platform"
      ;;
  esac
}

# 功能：按需要注入 `PGPASSWORD` 并运行或预览命令。
# 入参：第一个参数是 dry-run 标志，其余为命令数组。
# 返回：dry-run 时只输出命令；真实执行时返回目标命令退出状态。
run_pg_command() {
  local dry_run="$1"
  shift

  if [[ "$dry_run" == "1" ]]; then
    print_command_preview "$@"
    return 0
  fi

  if [[ -n "${DB_PASSWORD:-}" ]]; then
    PGPASSWORD="$DB_PASSWORD" "$@"
  else
    "$@"
  fi
}

# 功能：识别恢复输入类型。
# 入参：$1 为输入路径。
# 返回：输出 `sql`、`archive`、`directory` 或 `unknown`。
detect_restore_kind() {
  local input_path="$1"

  if [[ -d "$input_path" ]]; then
    printf 'directory\n'
    return 0
  fi

  case "${input_path##*.}" in
    sql) printf 'sql\n' ;;
    dump|backup|tar) printf 'archive\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# 功能：执行 PostgreSQL 备份命令。
# 入参：支持连接参数、输出路径、格式和过滤参数。
# 返回：dry-run 时输出命令；真实执行时运行 `pg_dump`。
run_backup() {
  local db_host="${PGHOST:-127.0.0.1}"
  local db_port="${PGPORT:-5432}"
  local db_user="${PGUSER:-postgres}"
  local db_database="${PGDATABASE:-}"
  DB_PASSWORD="${PGPASSWORD:-}"
  local dry_run=0
  local output_path=""
  local format="custom"
  local jobs=""
  local schema=""
  local table=""
  local exclude_table=""
  local schema_only=0
  local data_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host) db_host="$2"; shift 2 ;;
      --port) db_port="$2"; shift 2 ;;
      --user) db_user="$2"; shift 2 ;;
      --password) DB_PASSWORD="$2"; shift 2 ;;
      --database) db_database="$2"; shift 2 ;;
      --output) output_path="$2"; shift 2 ;;
      --format) format="$2"; shift 2 ;;
      --jobs) jobs="$2"; shift 2 ;;
      --schema) schema="$2"; shift 2 ;;
      --table) table="$2"; shift 2 ;;
      --exclude-table) exclude_table="$2"; shift 2 ;;
      --schema-only) schema_only=1; shift ;;
      --data-only) data_only=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *)
        die "backup 不支持的参数: $1"
        ;;
    esac
  done

  [[ -n "$db_database" ]] || die 'backup 需要 --database。'
  [[ -n "$output_path" ]] || die 'backup 需要 --output。'
  [[ "$schema_only" -eq 1 && "$data_only" -eq 1 ]] && die '--schema-only 与 --data-only 不能同时使用。'
  [[ "$format" != "directory" && -n "$jobs" ]] && die '只有 directory 格式支持 --jobs。'

  if [[ "$dry_run" -ne 1 ]]; then
    has_command pg_dump || die '未找到 pg_dump，请先运行 install-hint 查看安装命令。'
  fi

  local -a cmd=(pg_dump -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database")
  case "$format" in
    plain) cmd+=(-Fp) ;;
    directory) cmd+=(-Fd) ;;
    tar) cmd+=(-Ft) ;;
    custom) cmd+=(-Fc) ;;
    *) die "不支持的备份格式: $format" ;;
  esac

  cmd+=(-f "$output_path")
  [[ -n "$schema" ]] && cmd+=(-n "$schema")
  [[ -n "$table" ]] && cmd+=(-t "$table")
  [[ -n "$exclude_table" ]] && cmd+=("--exclude-table=$exclude_table")
  [[ "$schema_only" -eq 1 ]] && cmd+=(-s)
  [[ "$data_only" -eq 1 ]] && cmd+=(-a)
  [[ -n "$jobs" ]] && cmd+=(-j "$jobs")

  run_pg_command "$dry_run" "${cmd[@]}"
}

# 功能：执行 PostgreSQL 恢复命令。
# 入参：支持连接参数、输入路径和常见恢复开关。
# 返回：dry-run 时输出命令；真实执行时运行 `psql` 或 `pg_restore`。
run_restore() {
  local db_host="${PGHOST:-127.0.0.1}"
  local db_port="${PGPORT:-5432}"
  local db_user="${PGUSER:-postgres}"
  local db_database="${PGDATABASE:-}"
  DB_PASSWORD="${PGPASSWORD:-}"
  local dry_run=0
  local input_path=""
  local clean=0
  local if_exists=0
  local no_owner=0
  local no_privileges=0
  local schema=""
  local table=""
  local jobs=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host) db_host="$2"; shift 2 ;;
      --port) db_port="$2"; shift 2 ;;
      --user) db_user="$2"; shift 2 ;;
      --password) DB_PASSWORD="$2"; shift 2 ;;
      --database|--target-database) db_database="$2"; shift 2 ;;
      --input) input_path="$2"; shift 2 ;;
      --clean) clean=1; shift ;;
      --if-exists) if_exists=1; shift ;;
      --no-owner) no_owner=1; shift ;;
      --no-privileges) no_privileges=1; shift ;;
      --schema) schema="$2"; shift 2 ;;
      --table) table="$2"; shift 2 ;;
      --jobs) jobs="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *)
        die "restore 不支持的参数: $1"
        ;;
    esac
  done

  [[ -n "$db_database" ]] || die 'restore 需要 --database 或 --target-database。'
  [[ -n "$input_path" ]] || die 'restore 需要 --input。'
  [[ -e "$input_path" ]] || die "恢复输入不存在: $input_path"

  local restore_kind
  restore_kind="$(detect_restore_kind "$input_path")"

  case "$restore_kind" in
    sql)
      if [[ "$dry_run" -ne 1 ]]; then
        has_command psql || die '未找到 psql，请先运行 install-hint 查看安装命令。'
      fi
      local -a sql_cmd=(psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database" -v ON_ERROR_STOP=1 -f "$input_path")
      run_pg_command "$dry_run" "${sql_cmd[@]}"
      ;;
    archive|directory)
      if [[ "$dry_run" -ne 1 ]]; then
        has_command pg_restore || die '未找到 pg_restore，请先运行 install-hint 查看安装命令。'
      fi
      local -a restore_cmd=(pg_restore -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database")
      [[ "$clean" -eq 1 ]] && restore_cmd+=(--clean)
      [[ "$if_exists" -eq 1 ]] && restore_cmd+=(--if-exists)
      [[ "$no_owner" -eq 1 ]] && restore_cmd+=(--no-owner)
      [[ "$no_privileges" -eq 1 ]] && restore_cmd+=(--no-privileges)
      [[ -n "$schema" ]] && restore_cmd+=(-n "$schema")
      [[ -n "$table" ]] && restore_cmd+=(-t "$table")
      [[ -n "$jobs" ]] && restore_cmd+=(-j "$jobs")
      restore_cmd+=("$input_path")
      run_pg_command "$dry_run" "${restore_cmd[@]}"
      ;;
    *)
      die "不支持的恢复输入类型: $input_path"
      ;;
  esac
}

# 功能：按子命令分发脚本入口。
# 入参：第一个参数为子命令，其余参数透传给对应处理函数。
# 返回：执行对应子命令或输出帮助。
main() {
  local command_name="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$command_name" in
    help|-h|--help)
      print_usage
      ;;
    install-hint)
      install_hint "$@"
      ;;
    backup)
      run_backup "$@"
      ;;
    restore)
      run_restore "$@"
      ;;
    *)
      die "未知命令: $command_name"
      ;;
  esac
}

main "$@"
