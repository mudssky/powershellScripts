# LiteLLM claw OpenAI fallback Implementation Plan

## Checklist

- [x] 在 `litellm.local.yaml` 新增 `claw-plan`、`claw-glmplan-5.1`、`claw-deepseek-v4-flash` 三条模型路由。
- [x] 在 `newapi.yaml` 同步新增同一组三条模型路由。
- [x] 在两份 YAML 的 `router_settings.fallbacks` 中新增：
  - `claw-plan -> claw-deepseek-v4-flash`
  - `claw-glmplan-5.1 -> claw-deepseek-v4-flash`
- [x] 为 `claw-deepseek-v4-flash` 配置 `reasoning_effort: "max"`，默认启用最大思考模式。
- [x] 在 `compose.yaml` 注入 `DEEPSEEK_OPENAI_API_BASE`，默认 `https://api.deepseek.com/v1`。
- [x] 在 `.env.example` 与 `.env.production.example` 增加 `DEEPSEEK_OPENAI_API_BASE` 示例和说明。
- [x] 更新 `litellm.md`，说明 `claw-` 路由用途、模型名、环境变量、fallback 和验证命令。
- [x] 按需更新 `.trellis/spec/infra/litellm-gateway.md`，把 `claw-` 路由契约纳入未来修改规范。
- [x] 验证 YAML 可解析，并检查两份配置的 `claw-` 路由保持一致。
- [x] 运行根目录 `pnpm qa`。

## Validation Commands

```bash
python - <<'PY'
import yaml
from pathlib import Path
for path in [
    Path("ai/gateway/litellm/litellm.local.yaml"),
    Path("ai/gateway/litellm/newapi.yaml"),
]:
    data = yaml.safe_load(path.read_text())
    names = [item["model_name"] for item in data["model_list"]]
    for name in ["claw-plan", "claw-glmplan-5.1", "claw-deepseek-v4-flash"]:
        assert name in names, (path, name)
print("LiteLLM YAML claw routes ok")
PY

pnpm qa
```

## Risky Files and Rollback Points

- `ai/gateway/litellm/litellm.local.yaml` 与 `ai/gateway/litellm/newapi.yaml`：模型组和 fallback 顺序必须保持在全局 `*` 之前，避免被通配路由吞掉。
- `ai/gateway/litellm/compose.yaml`：只新增白名单环境变量，不改变现有密钥注入行为。
- `.trellis/spec/infra/litellm-gateway.md`：只补充 `claw-` OpenAI 兼容契约，不改 Claude Code thinking sanitizer 合同。

## Follow-up Checks Before Start

- 确认用户已认可本计划。
- 执行 Phase 1.4 `task.py start` 后再进入实现阶段。
