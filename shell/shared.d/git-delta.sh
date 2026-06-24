#!/bin/bash
# ========================================================================
# 文件: git-delta.sh
# 作用: 在交互式终端启用 git-delta 作为 git 的 diff pager。
#
# 设计意图（对应与用户讨论的 agent 兼容性）:
#   delta 配置分两部分——
#   1. 非 pager 部分（diff.colorMoved / merge.conflictStyle / delta.* 选项）
#      已写入 ~/.gitconfig，这些不调外部程序、对 agent 零影响。
#   2. pager 部分（让 git diff 走 delta）刻意「不」写入全局 [core] pager，
#      而是经 GIT_PAGER 环境变量在此处按 TTY 守护启用。
#
#   这样做的理由：agent 执行命令时若检测到无 TTY（如管道/重定向捕获），
#   GIT_PAGER 不会被设成 delta，git 输出纯文本，agent 解析不受 ANSI 色码干扰；
#   仅在真正的交互式终端（[ -t 1 ]）才启用 delta 美化。
#
# 加载顺序说明:
#   本文件只做条件 export，无函数依赖，无加载顺序要求。
# 兼容性: bash 与 zsh 双 shell。
# ========================================================================

# 仅当: (1) 是真正的交互式终端 stdout (-t 1)
#       (2) 已安装 delta
#   两个条件同时满足时，才把 GIT_PAGER 指向 delta。
# 否则保持 GIT_PAGER 为空/继承，git 回退到默认行为（纯文本或系统 pager）。
if [ -t 1 ] && command -v delta >/dev/null 2>&1; then
  export GIT_PAGER=delta
fi
