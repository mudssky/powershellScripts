#!/bin/bash

# ========================================================
# 脚本名称: manage-shell-snippet.sh
# 作用: 管理 ~/.bashrc.d/ 下的配置片段，并确保主 bashrc/zshrc 能加载它们
#       自动同步当前脚本同级目录 .bashrc.d/ 下的所有 .sh 文件
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

# 获取脚本所在目录 (兼容软链接)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SOURCE_SNIPPETS_DIR="$SCRIPT_DIR/.bashrc.d"

# --------------------------------------------------------
# 帮助文档
# --------------------------------------------------------
usage() {
    echo -e "${BLUE}Usage:${NC} $SCRIPT_NAME [OPTIONS]"
    echo
    echo -e "自动同步 ${YELLOW}$SOURCE_SNIPPETS_DIR${NC} 下的脚本到 ${YELLOW}$CONFIG_DIR${NC}"
    echo -e "并确保 ${YELLOW}~/.bashrc${NC} 和 ${YELLOW}~/.zshrc${NC} 包含加载逻辑。"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo -e "  -h, --help              显示此帮助信息"
    echo -e "  -n, --dry-run           模拟执行，不进行实际写入"
    echo -e "  -e, --exclude <pattern> 排除符合模式的文件 (可多次使用)"
    echo -e "                          例如: -e 'proxy.sh' -e 'test*.sh'"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  $SCRIPT_NAME                    # 正常同步所有文件"
    echo -e "  $SCRIPT_NAME --dry-run          # 仅查看会发生什么"
    echo -e "  $SCRIPT_NAME -e proxy.sh        # 同步但排除 proxy.sh"
    echo
}

# --------------------------------------------------------
# 日志函数
# --------------------------------------------------------
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_dry()  { echo -e "${BLUE}[DRY]${NC}  $1"; }

# --------------------------------------------------------
# 功能函数
# --------------------------------------------------------

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

sync_snippets() {
    if [ ! -d "$SOURCE_SNIPPETS_DIR" ]; then
        log_warn "未找到源配置目录: $SOURCE_SNIPPETS_DIR"
        log_warn "请确保脚本同级目录下存在 .bashrc.d 文件夹。"
        return
    fi

    log_info "开始同步配置片段..."
    if [ ${#EXCLUDE_LIST[@]} -gt 0 ]; then
        echo -e "    ${YELLOW}排除列表: ${EXCLUDE_LIST[*]}${NC}"
    fi

    shopt -s nullglob
    local count=0
    
    for file in "$SOURCE_SNIPPETS_DIR"/*.sh; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            
            if is_excluded "$filename"; then
                log_info "跳过 (已排除): $filename"
                continue
            fi

            target_path="$CONFIG_DIR/$filename"
            
            if [ "$DRY_RUN" = true ]; then
                log_dry "创建软链接 $filename -> $target_path"
            else
                ln -sf "$file" "$target_path"
                log_info "已创建软链接: $filename"
            fi
            ((count++))
        fi
    done
    shopt -u nullglob
    
    if [ "$count" -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
             log_dry "没有文件会被同步。"
        else
             log_warn "没有文件被同步。"
        fi
    else
        log_info "同步完成，共处理 $count 个文件。"
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

ensure_dir
# 确保 .bashrc 存在并添加加载器
ensure_loader "$HOME/.bashrc" true
# 如果 .zshrc 存在则添加加载器 (不强制创建)
ensure_loader "$HOME/.zshrc" false

sync_snippets
