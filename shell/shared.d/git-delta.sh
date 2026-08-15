#!/bin/bash
# ======================================================================
# 文件：git-delta.sh
# 作用：仅在真实交互终端启用 git-delta 作为 git pager。
# 兼容性：Bash / Zsh。
# 加载方式：条件 export，无函数依赖与加载顺序要求。
# ======================================================================

# -- interactive pager --------------------------------------------------
# 仅在 stdout 为 TTY 且 delta 已安装时设置 GIT_PAGER，避免 agent 或管道输出混入 ANSI。
if [ -t 1 ] && command -v delta >/dev/null 2>&1; then
  export GIT_PAGER=delta
fi
