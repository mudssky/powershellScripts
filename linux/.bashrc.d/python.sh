uv-iu() {
  # 1. 获取过时包列表 (需安装 jq 和 fzf)
  # 2. fzf 多选
  updates=$(uv pip list --outdated --format=json | \
    jq -r '.[].name' | \
    fzf --multi --preview 'uv pip show {}' --header 'Select packages to UPGRADE (Tab to multi-select)')

  if [ -n "$updates" ]; then
    echo "Upgrading the following packages to latest version:"
    echo "$updates"
    
    # 3. 关键修改：加上 --upgrade 参数
    # 这会强制 uv 忽略旧的版本约束，将 pyproject.toml 更新为最新版
    echo "$updates" | xargs uv add --upgrade
  else
    echo "No packages selected."
  fi
}