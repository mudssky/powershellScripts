#!/bin/bash
# ======================================================================
# 文件：java.sh
# 作用：加载 SDKMAN 并让其管理 Java 工具链。
# 兼容性：Bash / Zsh。
# ======================================================================

# -- SDKMAN -------------------------------------------------------------
export SDKMAN_DIR="$HOME/.sdkman"
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
fi
