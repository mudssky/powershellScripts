#!/bin/bash

# ========================================================
# 脚本名称: deploy.sh
# 作用: 管理 ~/.bashrc.d/ 下的配置片段，并确保主 bashrc/zshrc 能加载它们
#       自动同步 shared.d/ + bash.d/ 或 zsh.d/ 的配置片段
# ========================================================

# 配置
CONFIG_DIR="$HOME/.bashrc.d"
SCRIPT_NAME=$(basename "$0")

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
DRY_RUN=false
EXCLUDE_LIST=()
SHELL_TYPE=""

# 获取脚本所在目录 (兼容软链接)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SHARED_DIR="$SCRIPT_DIR/shared.d"
BASH_SPECIFIC_DIR="$SCRIPT_DIR/bash.d"
ZSH_SPECIFIC_DIR="$SCRIPT_DIR/zsh.d"

# --------------------------------------------------------
# 帮助文档
# --------------------------------------------------------
usage() {
    echo -e "${BLUE}Usage:${NC} $SCRIPT_NAME [OPTIONS]"
    echo
    echo -e "自动同步 ${YELLOW}shell/shared.d/${NC} + shell 专属片段到 ${YELLOW}$CONFIG_DIR${NC}"
    echo -e "并确保 ${YELLOW}~/.bashrc${NC} 或 ${YELLOW}~/.zshrc${NC} 包含加载逻辑。"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo -e "  -h, --help              显示此帮助信息"
    echo -e "  -n, --dry-run           模拟执行，不进行实际写入"
    echo -e "  -s, --shell <bash|zsh>  指定目标 shell (默认: 自动检测)"
    echo -e "  -e, --exclude <pattern> 排除符合模式的文件 (可多次使用)"
    echo -e "                          例如: -e 'proxy.sh' -e 'test*.sh'"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  $SCRIPT_NAME                       # 正常同步 (自动检测 shell)"
    echo -e "  $SCRIPT_NAME --dry-run             # 仅查看会发生什么"
    echo -e "  $SCRIPT_NAME --shell zsh           # 强制按 Zsh 模式部署"
    echo -e "  $SCRIPT_NAME -e proxy.sh           # 同步但排除 proxy.sh"
    echo
}

# --------------------------------------------------------
# 日志函数
# --------------------------------------------------------
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_dry()  { echo -e "${BLUE}[DRY]${NC}  $1" >&2; }

# --------------------------------------------------------
# 功能函数
# --------------------------------------------------------

detect_shell() {
    if [ -n "$SHELL_TYPE" ]; then
        return
    fi
    SHELL_TYPE=$(basename "$SHELL")
    if [ "$SHELL_TYPE" != "bash" ] && [ "$SHELL_TYPE" != "zsh" ]; then
        log_warn "无法识别默认 shell '$SHELL_TYPE'，将使用 bash 模式"
        SHELL_TYPE="bash"
    fi
}

ensure_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
             log_dry "创建目录: $CONFIG_DIR"
        else
             mkdir -p "$CONFIG_DIR"
             log_info "已创建配置目录: $CONFIG_DIR"
        fi
    fi
}

ensure_loader() {
    local RC_FILE="$1"
    local CREATE_IF_MISSING="$2"
    local LOADER_MARK="# Load modular configuration files from ~/.bashrc.d"

    if [ ! -f "$RC_FILE" ]; then
        if [ "$CREATE_IF_MISSING" = true ]; then
            if [ "$DRY_RUN" = true ]; then
                log_dry "创建 $RC_FILE (因为不存在)"
            else
                touch "$RC_FILE"
                log_info "已创建 $RC_FILE"
            fi
        else
            # 如果文件不存在且不强制创建，则跳过
            return
        fi
    fi

    if grep -Fq "$LOADER_MARK" "$RC_FILE"; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry "向 $RC_FILE 添加加载逻辑"
        return
    fi

    log_info "检测到未配置加载器，正在向 $RC_FILE 添加加载逻辑..."

    cat << 'EOF' >> "$RC_FILE"

# Load modular configuration files from ~/.bashrc.d
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME/.bashrc.d/"*.sh; do
        if [ -f "$rc" ]; then
            source "$rc"
        fi
    done
fi
EOF
    log_info "加载逻辑已添加至 $RC_FILE。"
}

is_excluded() {
    local filename="$1"
    for pattern in "${EXCLUDE_LIST[@]}"; do
        # 使用 bash 的 [[ string == pattern ]] 进行通配符匹配
        if [[ "$filename" == $pattern ]]; then
            return 0 # true, excluded
        fi
    done
    return 1 # false, not excluded
}

# 清理 ~/.bashrc.d/ 中指向不存在路径的旧 symlink
cleanup_stale_symlinks() {
    if [ ! -d "$CONFIG_DIR" ]; then
        return
    fi

    local stale_count=0
    for link in "$CONFIG_DIR"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            local target
            target=$(readlink "$link")
            if [ "$DRY_RUN" = true ]; then
                log_dry "删除失效 symlink: $(basename "$link") -> $target"
            else
                rm "$link"
                log_info "已删除失效 symlink: $(basename "$link") -> $target"
            fi
            ((stale_count++))
        fi
    done

    if [ "$stale_count" -gt 0 ]; then
        log_info "清理了 $stale_count 个失效 symlink。"
    fi
}

# 同步指定目录中的片段到 ~/.bashrc.d/
# $1: 源目录
# $2: 文件扩展名 (sh 或 zsh)
# $3: 是否将 .zsh 重命名为 .sh (true/false)
sync_dir() {
    local source_dir="$1"
    local ext="$2"
    local rename_to_sh="$3"

    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    shopt -s nullglob
    local count=0

    for file in "$source_dir"/*."$ext"; do
        if [ -f "$file" ]; then
            local filename
            filename=$(basename "$file")

            if is_excluded "$filename"; then
                log_info "跳过 (已排除): $filename"
                continue
            fi

            local target_name="$filename"
            if [ "$rename_to_sh" = true ]; then
                # .zsh -> .sh，使 ~/.bashrc.d/ loader 能加载
                target_name="${filename%.zsh}.sh"
            fi
            local target_path="$CONFIG_DIR/$target_name"

            if [ "$DRY_RUN" = true ]; then
                log_dry "创建软链接 $filename -> $target_path"
            else
                ln -sf "$file" "$target_path"
                log_info "已创建软链接: $filename -> $target_name"
            fi
            ((count++))
        fi
    done
    shopt -u nullglob

    echo "$count"
}

sync_snippets() {
    log_info "开始同步配置片段 (shell: $SHELL_TYPE)..."
    if [ ${#EXCLUDE_LIST[@]} -gt 0 ]; then
        echo -e "    ${YELLOW}排除列表: ${EXCLUDE_LIST[*]}${NC}" >&2
    fi

    local total=0

    # 1. 同步 shared.d/
    if [ ! -d "$SHARED_DIR" ]; then
        log_warn "未找到源配置目录: $SHARED_DIR"
        return
    fi
    log_info "同步 shared.d/ (通用片段)..."
    local shared_count
    shared_count=$(sync_dir "$SHARED_DIR" "sh" false)
    total=$((total + shared_count))

    # 2. 根据 shell 类型同步专属片段
    if [ "$SHELL_TYPE" = "zsh" ]; then
        if [ -d "$ZSH_SPECIFIC_DIR" ]; then
            log_info "同步 zsh.d/ (Zsh 专属片段)..."
            local zsh_count
            zsh_count=$(sync_dir "$ZSH_SPECIFIC_DIR" "zsh" true)
            total=$((total + zsh_count))
        fi
    else
        if [ -d "$BASH_SPECIFIC_DIR" ]; then
            log_info "同步 bash.d/ (Bash 专属片段)..."
            local bash_count
            bash_count=$(sync_dir "$BASH_SPECIFIC_DIR" "sh" false)
            total=$((total + bash_count))
        fi
    fi

    if [ "$total" -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
             log_dry "没有文件会被同步。"
        else
             log_warn "没有文件被同步。"
        fi
    else
        log_info "同步完成，共处理 $total 个文件。"
    fi
}

# --------------------------------------------------------
# 主逻辑
# --------------------------------------------------------

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_TYPE="$2"
                if [ "$SHELL_TYPE" != "bash" ] && [ "$SHELL_TYPE" != "zsh" ]; then
                    log_err "--shell 参数仅支持 bash 或 zsh"
                    exit 1
                fi
                shift 2
            else
                log_err "参数 --shell 需要一个值 (bash 或 zsh)"
                exit 1
            fi
            ;;
        -e|--exclude)
            if [[ -n "$2" && "$2" != -* ]]; then
                EXCLUDE_LIST+=("$2")
                shift 2
            else
                log_err "参数 --exclude 需要一个模式值"
                exit 1
            fi
            ;;
        *)
            log_err "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

detect_shell
log_info "检测到目标 shell: $SHELL_TYPE"

ensure_dir

# 清理旧的失效 symlink
cleanup_stale_symlinks

# 根据 shell 类型确保对应的 rc 文件有 loader
if [ "$SHELL_TYPE" = "zsh" ]; then
    ensure_loader "$HOME/.zshrc" true
    # 也处理 .bashrc（如果存在）
    ensure_loader "$HOME/.bashrc" false
else
    ensure_loader "$HOME/.bashrc" true
    # 也处理 .zshrc（如果存在）
    ensure_loader "$HOME/.zshrc" false
fi

sync_snippets
