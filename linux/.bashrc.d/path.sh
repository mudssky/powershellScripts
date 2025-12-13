#!/bin/bash

# 添加项目根目录下的bin目录到PATH中（如果PATH中没有的话）

# 函数：检查路径是否在PATH中
is_path_included() {
    local path_to_check="$1"
    [[ ":$PATH:" == *":$path_to_check:"* ]]
}

# 函数：添加路径到PATH（如果不存在）
add_to_path() {
    local path_to_add="$1"
    if ! is_path_included "$path_to_add"; then
        export PATH="$path_to_add:$PATH"
        echo "已添加 $path_to_add 到 PATH"
        return 0
    else
        echo "$path_to_add 已在 PATH 中"
        return 1
    fi
}

# 函数：添加项目根目录下的bin目录
add_project_bin_to_path() {
    # 获取脚本所在目录的父目录（项目根目录）
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$(dirname "$script_dir")")"
    local bin_dir="$project_root/bin"
    
    if [ -d "$bin_dir" ]; then
        add_to_path "$bin_dir"
    else
        echo "项目根目录下的bin目录不存在: $bin_dir"
        return 1
    fi
}

# 执行添加操作
add_project_bin_to_path