#!/usr/bin/env bash
# shell/shared.d/env.local.example.sh
#
# 本机私有环境变量清单（可提交模板）
# ------------------------------------------------------------
# 真实文件：
#   shell/shared.d/env.local.sh          # 仓库内本机私有，已被 shell/.gitignore 的 *.local.sh 忽略
#   ~/.bashrc.d/env.local.sh             # 通常是指向上面的 symlink（shell/deploy.sh 同步）
#
# 加载链：
#   zsh/bash: ~/.zprofile / ~/.zshrc / ~/.bashrc → source ~/.bashrc.d/*.sh
#   pwsh:     profile/features/environment.ps1 解析同一份 env.local.sh 的 export 行
#             （另可选 profile/env.ps1，仓库根 .gitignore 已忽略 env.ps1）
#
# 用法：
#   cp shell/shared.d/env.local.example.sh shell/shared.d/env.local.sh
#   编辑真实值后执行: ./shell/deploy.sh
# ------------------------------------------------------------
# 约定：
# - 只放本机/密钥/绝对路径；不要提交真实 env.local.sh
# - 大体积缓存优先落到 /Volumes/Data（Mac Mini 数据盘）
# - 路径类变量应在数据盘已挂载时再 export
# ------------------------------------------------------------

# ===== API keys / tokens（占位符，勿提交真实值）=====
export XH_API_KEY='sk-REPLACE_ME'
export LOCAL_API_KEY='sk-REPLACE_ME'
export GLM_CODING_PLAN_API_KEY='REPLACE_ME'
export CONTEXT7_API_KEY='ctx7sk-REPLACE_ME'

# ===== 本机路径：Hermes =====
# 程序本体仍在官方安装目录；配置与状态放数据盘。
export HERMES_HOME="/Volumes/Data/agents/hermes"

# ===== 本机路径：Rust 编译 / 下载缓存（Mac Mini）=====
# sccache：跨项目编译缓存
# CARGO_HOME：registry + git 下载缓存（体积大）
# 不要全局设置 CARGO_TARGET_DIR（多项目会互相踩 target）
# RUSTUP_HOME 可选；默认留在 ~/.rustup
#
# 双模式（日常默认 A）：
#   A. 日常单项目热改：保留 Cargo incremental（默认，不设 CARGO_INCREMENTAL）
#      - 同项目改代码重编通常更快
#      - sccache 对 lib 依赖仍可能命中，但对 incremental 调用不缓存
#   B. 跨项目 / clean / 榨 sccache 命中率：关闭 incremental
#      - 取消下面 CARGO_INCREMENTAL=0 的注释，或单次命令：
#        CARGO_INCREMENTAL=0 cargo build
#      - 也可用 $CARGO_HOME/config.toml 里 [build] incremental = false
# 说明见 sccache docs/Rust.md：incremental 与 sccache 可靠缓存互斥
if [ -d "/Volumes/Data" ]; then
    export SCCACHE_DIR="/Volumes/Data/cache/sccache"
    export CARGO_HOME="/Volumes/Data/cache/cargo"
    # export RUSTUP_HOME="/Volumes/Data/cache/rustup"
    mkdir -p "$SCCACHE_DIR" "$CARGO_HOME" 2>/dev/null || true
fi

# 需要已安装 sccache（brew install sccache）。未安装时请注释掉，否则 cargo 会失败。
export RUSTC_WRAPPER="sccache"

# --- 模式 B 开关（默认注释 = 模式 A，保留 incremental）---
# export CARGO_INCREMENTAL=0

# ===== 本机 alias（仅 bash/zsh；pwsh 不会导入 alias 行）=====
# alias skill-add-personal='npx skills add http://macmini:30001/mudssky/agent-skills.git'
# 单次强制走 sccache 友好模式（不改会话默认）：
# alias cargo-cold='CARGO_INCREMENTAL=0 cargo'
