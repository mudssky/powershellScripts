#!/bin/bash

# 配置应用脚本 - 通过软链接快速应用shell配置文件
# 作者: mudssky
# 用途: 快速应用config目录下的配置文件到用户主目录

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查配置目录是否存在
check_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        log_error "配置目录不存在: $CONFIG_DIR"
        exit 1
    fi
}

# 备份现有配置文件
backup_existing_config() {
    local config_file="$1"
    local home_path="$HOME/$config_file"
    
    if [ -e "$home_path" ] && [ ! -L "$home_path" ]; then
        local backup_path="${home_path}.backup.$(date +%Y%m%d_%H%M%S)"
        log_warning "备份现有配置文件: $home_path -> $backup_path"
        mv "$home_path" "$backup_path"
    elif [ -L "$home_path" ]; then
        log_info "移除现有软链接: $home_path"
        rm "$home_path"
    fi
}

# 创建软链接
create_symlink() {
    local config_file="$1"
    local source_path="$CONFIG_DIR/$config_file"
    local target_path="$HOME/$config_file"
    
    if [ ! -f "$source_path" ]; then
        log_error "配置文件不存在: $source_path"
        return 1
    fi
    
    # 备份现有配置
    backup_existing_config "$config_file"
    
    # 创建软链接
    ln -s "$source_path" "$target_path"
    
    if [ $? -eq 0 ]; then
        log_success "成功创建软链接: $target_path -> $source_path"
        return 0
    else
        log_error "创建软链接失败: $target_path"
        return 1
    fi
}

# 应用zsh配置
apply_zsh_config() {
    log_info "应用 Zsh 配置..."
    
    if create_symlink ".zshrc"; then
        if [ -f "$CONFIG_DIR/.p10k.zsh" ]; then
            create_symlink ".p10k.zsh"
        fi
        log_success "Zsh 配置应用完成"
    else
        log_error "Zsh 配置应用失败"
        return 1
    fi
}

# 应用bash配置
apply_bash_config() {
    log_info "应用 Bash 配置..."
    
    if create_symlink ".bashrc"; then
        log_success "Bash 配置应用完成"
    else
        log_error "Bash 配置应用失败"
        return 1
    fi
}

# 应用所有可用配置
apply_all_configs() {
    log_info "应用所有可用配置..."
    
    local applied_count=0
    
    # 检查并应用zsh配置
    if [ -f "$CONFIG_DIR/.zshrc" ]; then
        apply_zsh_config && ((applied_count++))
    fi
    
    # 检查并应用bash配置
    if [ -f "$CONFIG_DIR/.bashrc" ]; then
        apply_bash_config && ((applied_count++))
    fi
    
    # 应用其他配置文件
    for config_file in "$CONFIG_DIR"/.*; do
        if [ -f "$config_file" ]; then
            local filename=$(basename "$config_file")
            case "$filename" in
                ".zshrc"|"p10k.zsh"|"bashrc")
                    # 已经处理过的文件，跳过
                    ;;
                "."|"..") 
                    # 跳过当前目录和父目录
                    ;;
                *)
                    if create_symlink "$filename"; then
                        ((applied_count++))
                    fi
                    ;;
            esac
        fi
    done
    
    log_success "总共应用了 $applied_count 个配置文件"
}

# 列出可用配置
list_configs() {
    log_info "可用的配置文件:"
    
    if [ -d "$CONFIG_DIR" ]; then
        for config_file in "$CONFIG_DIR"/.*; do
            if [ -f "$config_file" ]; then
                local filename=$(basename "$config_file")
                case "$filename" in
                    "."|"..") 
                        # 跳过当前目录和父目录
                        ;;
                    *)
                        local target_path="$HOME/$filename"
                        if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$config_file" ]; then
                            echo -e "  ${GREEN}✓${NC} $filename (已链接)"
                        else
                            echo -e "  ${YELLOW}○${NC} $filename (未链接)"
                        fi
                        ;;
                esac
            fi
        done
    else
        log_error "配置目录不存在: $CONFIG_DIR"
    fi
}

# 显示帮助信息
show_help() {
    echo "配置应用脚本 - 通过软链接快速应用shell配置文件"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  zsh, z          应用 Zsh 配置 (.zshrc, .p10k.zsh)"
    echo "  bash, b         应用 Bash 配置 (.bashrc)"
    echo "  all, a          应用所有可用配置"
    echo "  list, l         列出所有可用配置"
    echo "  help, h         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 zsh          # 应用 Zsh 配置"
    echo "  $0 bash         # 应用 Bash 配置"
    echo "  $0 all          # 应用所有配置"
    echo "  $0 list         # 列出可用配置"
    echo ""
    echo "配置文件位置: $CONFIG_DIR"
}

# 主函数
main() {
    # 检查配置目录
    check_config_dir
    
    # 解析命令行参数
    case "${1:-help}" in
        "zsh"|"z")
            apply_zsh_config
            ;;
        "bash"|"b")
            apply_bash_config
            ;;
        "all"|"a")
            apply_all_configs
            ;;
        "list"|"l")
            list_configs
            ;;
        "help"|"h"|"")
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"