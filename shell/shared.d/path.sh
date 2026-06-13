#!/bin/bash

# 添加项目根目录下的bin目录到PATH中（如果PATH中没有的话）

# 函数：检查路径是否在 PATH 中
# 参数：
#   $1 - 需要检查的路径。
# 返回：
#   路径已存在返回 0，否则返回 1。
is_path_included() {
    local path_to_check="$1"
    [[ ":$PATH:" == *":$path_to_check:"* ]]
}

# 函数：添加路径到 PATH（如果不存在）
# 参数：
#   $1 - 需要加入 PATH 的路径。
# 返回：
#   新增路径返回 0，路径已存在返回 1。
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

# 函数：静默添加路径到 PATH（如果不存在）
# 参数：
#   $1 - 需要加入 PATH 的路径。
# 返回：
#   新增路径返回 0，路径已存在返回 1。
add_to_path_silent() {
    local path_to_add="$1"
    if ! is_path_included "$path_to_add"; then
        export PATH="$path_to_add:$PATH"
        return 0
    fi
}

# 函数：添加项目根目录下的bin目录
# 参数：
#   无。
# 返回：
#   成功新增仓库 bin 路径返回 0；路径已存在或无法解析脚本路径返回 1。
add_project_bin_to_path() {
    # 获取脚本文件的真实物理路径（解决软链接问题）
    local source="${BASH_SOURCE[0]}"
    # 兼容 Zsh
    if [ -z "$source" ] && [ -n "$ZSH_VERSION" ]; then
        source="${(%):-%x}"
    fi

    while [ -h "$source" ]; do
        local dir="$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    local script_dir="$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
    if [ -z "$script_dir" ]; then
        return 1
    fi

    local project_root="$(dirname "$(dirname "$script_dir")")"
    local bin_dir="$project_root/bin"

    # 即使 bin 目录尚未生成也预先加入 PATH，后续生成 shim 后当前 shell 可直接发现。
    add_to_path_silent "$bin_dir"
}

# 执行添加操作
add_project_bin_to_path
# 添加 cargo 二进制目录到 PATH（如果存在）
add_to_path_silent "$HOME/.cargo/bin"
