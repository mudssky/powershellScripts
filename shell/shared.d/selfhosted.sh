# ======================================================================
# 文件：selfhosted.sh
# 作用：提供依赖自建服务的 CLI 快捷入口。
# 兼容性：Bash / Zsh。
# ======================================================================

# -- agent skills -------------------------------------------------------
# ----------------------------------------------------------------------
# skillhub — 通过内网 Forgejo npm registry 调用 @agent-skills/cli。
#
# 设计意图：
#   显式区分公共 npm registry 与 @agent-skills scope registry，使调用不依赖
#   用户级 .npmrc，同时避免公共依赖被错误地发送到内网 registry 查询。
#
# 参数：$@ — 原样传给 skillhub CLI。
# 输出：stderr — npx 缺失时输出安装提示。
# 返回码：透传 npx/skillhub 退出码；npx 不存在时返回 0。
# ----------------------------------------------------------------------
skillhub() {
  if ! command -v npx >/dev/null 2>&1; then
    printf '[skillhub] 未检测到 npx，请先安装 Node.js/npm。\n' >&2
    return 0
  fi

  npx --yes \
    --registry https://registry.npmjs.org/ \
    --@agent-skills:registry=http://macmini:30001/api/packages/mudssky/npm/ \
    @agent-skills/cli "$@"
}
