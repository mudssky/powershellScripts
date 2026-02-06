# AI 相关的通用配置

# Claude Code 使用 GLM 模型的通用配置
function claude-glm() {
    ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic \
    API_TIMEOUT_MS=300000 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    claude --model glm-4.7 "$@"
}
