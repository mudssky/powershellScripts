#!/bin/zsh

# Hammerspoon Lua Scripts Loader
# 自动部署并应用仓库维护的 Hammerspoon Lua 配置。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HAMMERSPOON_CONFIG_DIR="$HOME/.hammerspoon"
SCRIPTS_TARGET_DIR="$HAMMERSPOON_CONFIG_DIR/scripts"
MANIFEST_FILE="$HAMMERSPOON_CONFIG_DIR/.powershellscripts-hammerspoon.manifest"

DRY_RUN=false
NO_LAUNCH=false
INSTALL_HAMMERSPOON=false

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run     只显示将执行的操作，不写入文件
  --no-launch   部署后不启动或重启 Hammerspoon
  --install     未检测到 Hammerspoon 时使用 Homebrew Cask 安装
  -h, --help    显示帮助
EOF
}

# 输出信息日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() { echo -e "${GREEN}✅ $1${NC}"; }

# 输出提醒日志。
# 入参：$1 日志内容。
# 返回值：无。
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# 输出错误日志。
# 入参：$1 日志内容。
# 返回值：无。
log_err() { echo -e "${RED}❌ $1${NC}" >&2; }

# 执行或展示命令。
# 入参：命令及其参数。
# 返回值：命令退出码。
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] $*${NC}"
        return 0
    fi

    "$@"
}

# 备份将被覆盖的文件。
# 入参：$1 文件路径。
# 返回值：无。
backup_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        return
    fi

    local backup_path="${file_path}.$(date +%Y-%m-%d_%H-%M-%S).bak"
    log_warn "备份现有文件: $backup_path"
    run_cmd cp "$file_path" "$backup_path"
}

# 复制文件并按需备份目标文件。
# 入参：$1 源文件；$2 目标文件；$3 是否备份 existing 目标。
# 返回值：无。
copy_file() {
    local source_file="$1"
    local target_file="$2"
    local should_backup="${3:-true}"

    if [ ! -f "$source_file" ]; then
        log_err "源文件不存在: $source_file"
        exit 1
    fi

    if [ "$should_backup" = true ]; then
        backup_file "$target_file"
    fi

    log_info "复制 $(basename "$source_file") -> $target_file"
    run_cmd cp "$source_file" "$target_file"
}

# 复制插件文件并登记 manifest。
# 入参：$1 插件源文件；$2 manifest 条目数组名；$3 复制计数变量名。
# 返回值：无。
copy_plugin_file() {
    local source_file="$1"
    local entries_name="$2"
    local count_name="$3"
    local relative_path="${source_file#$SCRIPT_DIR/}"
    local target_file="$SCRIPTS_TARGET_DIR/$relative_path"
    local target_dir
    target_dir="$(dirname "$target_file")"

    run_cmd mkdir -p "$target_dir"
    copy_file "$source_file" "$target_file" true

    eval "$entries_name+=(\"scripts/$relative_path\")"
    eval "$count_name=\$(( $count_name + 1 ))"
}

# 检测 Hammerspoon 是否已安装。
# 入参：无。
# 返回值：已安装返回 0，否则返回 1。
is_hammerspoon_installed() {
    open -Ra Hammerspoon >/dev/null 2>&1 && return 0

    [ -d "/Applications/Hammerspoon.app" ] && return 0
    [ -d "$HOME/Applications/Hammerspoon.app" ] && return 0
    [ -d "/opt/homebrew/Caskroom/hammerspoon" ] && return 0
    [ -d "/usr/local/Caskroom/hammerspoon" ] && return 0

    return 1
}

# 安装 Hammerspoon。
# 入参：无。
# 返回值：无。
install_hammerspoon() {
    if ! command -v brew >/dev/null 2>&1; then
        log_err "未找到 Homebrew，请先安装 Homebrew 或手动安装 Hammerspoon"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "将安装 Hammerspoon: brew install --cask hammerspoon"
    else
        log_info "安装 Hammerspoon: brew install --cask hammerspoon"
    fi
    run_cmd brew install --cask hammerspoon
}

# 读取上一轮托管文件清单。
# 入参：无。
# 返回值：逐行输出 manifest 内容。
read_manifest() {
    if [ -f "$MANIFEST_FILE" ]; then
        cat "$MANIFEST_FILE"
    fi
}

# 写入本轮托管文件清单。
# 入参：文件路径列表。
# 返回值：无。
write_manifest() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] 写入 manifest: $MANIFEST_FILE${NC}"
        printf '%s\n' "$@"
        return
    fi

    printf '%s\n' "$@" > "$MANIFEST_FILE"
}

# 判断数组中是否包含指定值。
# 入参：$1 目标值；其余参数为候选值。
# 返回值：包含返回 0，否则返回 1。
contains_value() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# 清理上一轮托管但本轮不再存在的文件。
# 入参：本轮 manifest 条目。
# 返回值：无。
cleanup_removed_managed_files() {
    local current_entries=("$@")
    local old_entry

    while IFS= read -r old_entry; do
        [ -z "$old_entry" ] && continue
        contains_value "$old_entry" "${current_entries[@]}" && continue

        local old_path="$HAMMERSPOON_CONFIG_DIR/$old_entry"
        if [ -f "$old_path" ]; then
            log_warn "删除已移除的托管文件: $old_path"
            run_cmd rm "$old_path"
        fi
    done < <(read_manifest)
}

# 部署 Hammerspoon 配置文件和脚本。
# 入参：无。
# 返回值：无。
deploy_files() {
    run_cmd mkdir -p "$HAMMERSPOON_CONFIG_DIR" "$SCRIPTS_TARGET_DIR"

    local init_source="$SCRIPT_DIR/init/init.lua"
    copy_file "$init_source" "$HAMMERSPOON_CONFIG_DIR/init.lua" true

    copy_file "$SCRIPT_DIR/config.lua" "$HAMMERSPOON_CONFIG_DIR/config.lua" true

    local local_config="$HAMMERSPOON_CONFIG_DIR/config.local.lua"
    if [ -f "$local_config" ]; then
        log_info "保留本机配置: $local_config"
    else
        copy_file "$SCRIPT_DIR/config.local.example.lua" "$local_config" false
    fi

    local managed_entries=("init.lua" "config.lua")
    local copied_count=0
    local plugin_file

    if [ -d "$SCRIPT_DIR/plugins" ]; then
        while IFS= read -r plugin_file; do
            [ -f "$plugin_file" ] || continue
            copy_plugin_file "$plugin_file" managed_entries copied_count
        done < <(find "$SCRIPT_DIR/plugins" -type f -name '*.lua' | sort)
    fi

    cleanup_removed_managed_files "${managed_entries[@]}"
    write_manifest "${managed_entries[@]}"

    if [ "$copied_count" -eq 0 ]; then
        log_warn "没有找到需要部署的插件脚本"
    else
        log_info "已部署 $copied_count 个插件脚本"
    fi
}

# 启动或重启 Hammerspoon。
# 入参：无。
# 返回值：无。
launch_hammerspoon() {
    if [ "$NO_LAUNCH" = true ]; then
        log_info "已跳过启动 Hammerspoon"
        return
    fi

    if pgrep -x "Hammerspoon" >/dev/null; then
        log_info "Hammerspoon 正在运行，重启以应用配置"
        run_cmd osascript -e 'tell application "Hammerspoon" to quit'
        if [ "$DRY_RUN" = false ]; then
            sleep 2
        fi
    else
        log_info "启动 Hammerspoon"
    fi

    run_cmd open -a Hammerspoon
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-launch)
            NO_LAUNCH=true
            shift
            ;;
        --install)
            INSTALL_HAMMERSPOON=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_err "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

echo -e "${BLUE}Hammerspoon Lua Scripts Loader${NC}"
echo -e "${BLUE}================================${NC}"

if ! is_hammerspoon_installed; then
    if [ "$INSTALL_HAMMERSPOON" = true ]; then
        install_hammerspoon
    else
        log_err "未检测到 Hammerspoon"
        echo -e "${YELLOW}请先执行: brew install --cask hammerspoon${NC}"
        echo -e "${YELLOW}或重新运行本脚本并添加 --install${NC}"
        exit 1
    fi
fi

if [ "$DRY_RUN" = true ]; then
    log_info "dry-run 模式下继续模拟部署"
else
    log_info "Hammerspoon 已安装"
fi

deploy_files
launch_hammerspoon

echo
log_info "Hammerspoon 配置部署完成"
echo -e "${BLUE}配置目录: $HAMMERSPOON_CONFIG_DIR${NC}"
echo -e "${BLUE}本机覆盖: $HAMMERSPOON_CONFIG_DIR/config.local.lua${NC}"
