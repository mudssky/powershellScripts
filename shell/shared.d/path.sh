#!/bin/bash
# ======================================================================
# 文件：path.sh
# 作用：按需把项目 bin 与 Cargo bin 目录加入 PATH。
# 兼容性：Bash / Zsh；通过 deploy.sh source。
# ======================================================================

# -- path helpers -------------------------------------------------------
# is_path_included — 判断路径是否已存在于 PATH。
# 参数：$1 — 待检查的路径。
# 返回码：路径已存在返回 0，否则返回 1。
is_path_included() {
    local path_to_check="$1"
    [[ ":$PATH:" == *":$path_to_check:"* ]]
}

# ----------------------------------------------------------------------
# add_to_path — 将路径加入 PATH，并在实际变更时提示。
#
# 参数：$1 — 待加入 PATH 的路径。
# 输出：stdout — 路径新增或已存在的提示。
# 副作用：路径不存在时更新 PATH。
# 返回码：新增路径返回 0，路径已存在返回 1。
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# add_to_path_silent — 将路径加入 PATH，不输出提示。
#
# 参数：$1 — 待加入 PATH 的路径。
# 副作用：路径不存在时更新 PATH。
# 返回码：新增路径返回 0；路径已存在时沿用函数末尾状态。
# ----------------------------------------------------------------------
add_to_path_silent() {
    local path_to_add="$1"
    if ! is_path_included "$path_to_add"; then
        export PATH="$path_to_add:$PATH"
        return 0
    fi
}

# ----------------------------------------------------------------------
# add_project_bin_to_path — 解析脚本真实路径并加入项目 bin 目录。
#
# 设计意图：兼容 deploy.sh 建立的软链接，并预先加入尚未生成的 bin 目录。
#
# 参数：无。
# 返回码：成功新增或已处理返回函数调用状态；无法解析脚本目录返回 1。
# ----------------------------------------------------------------------
add_project_bin_to_path() {
    # 获取脚本文件的真实物理路径（解决软链接问题）。
    local source="${BASH_SOURCE[0]}"
    # 兼容 Zsh。
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

# -- initialization -----------------------------------------------------
add_project_bin_to_path
# 添加 cargo 二进制目录到 PATH（优先 CARGO_HOME，兼容默认 ~/.cargo）。
add_to_path_silent "${CARGO_HOME:-$HOME/.cargo}/bin"
