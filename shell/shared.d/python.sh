# ======================================================================
# 文件：python.sh
# 作用：提供 uv pip 过时包的交互式升级命令。
# 兼容性：Bash / Zsh；需要 uv、jq 和 fzf。
# ======================================================================

# ----------------------------------------------------------------------
# uv-iu — 选择并升级过时的 Python 包。
#
# 参数：无。
# 输出：stdout — 待升级包列表或未选择提示。
# 副作用：通过 uv add --upgrade 修改项目依赖声明。
# 返回码：uv、fzf 或 xargs 的退出码。
# ----------------------------------------------------------------------
uv-iu() {
  updates=$(uv pip list --outdated --format=json | \
    jq -r '.[].name' | \
    fzf --multi --preview 'uv pip show {}' --header 'Select packages to UPGRADE (Tab to multi-select)')

  if [ -n "$updates" ]; then
    echo "Upgrading the following packages to latest version:"
    echo "$updates"
    
    # 使用 --upgrade 强制更新依赖声明，避免保留旧版本约束。
    echo "$updates" | xargs uv add --upgrade
  else
    echo "No packages selected."
  fi
}