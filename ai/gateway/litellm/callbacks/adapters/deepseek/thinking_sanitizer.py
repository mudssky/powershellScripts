"""DeepSeek Anthropic thinking 清洗 adapter。"""

from typing import Any

from callbacks.adapters.deepseek.thinking_sanitizer_core import (
    complete_input_dict,
    is_deepseek_anthropic_request,
    sanitize_request_context,
)
from callbacks.adapters.deepseek.thinking_sanitizer_logging import (
    log_sanitized_context,
)
from callbacks.framework.adapters import AdapterResult, SanitizerAdapter


class DeepSeekThinkingSanitizerAdapter(SanitizerAdapter):
    """在 DeepSeek Anthropic 请求发出前移除不兼容 thinking 历史。"""

    name = "deepseek_thinking_sanitizer"

    def should_sanitize_anthropic_messages(
        self,
        kwargs: dict[str, Any],
        call_type: Any,
        anthropic_messages_call_type: Any,
    ) -> bool:
        """判断当前 Anthropic messages 请求是否需要清理。

        Args:
            kwargs: LiteLLM hook 传入的模型调用上下文。
            call_type: 当前 LiteLLM 调用类型。
            anthropic_messages_call_type: LiteLLM Anthropic messages 调用类型常量。

        Returns:
            需要清理 DeepSeek Anthropic 请求时返回 True，否则返回 False。
        """
        return call_type == anthropic_messages_call_type and is_deepseek_anthropic_request(kwargs)

    async def async_pre_call_deployment_hook(
        self,
        kwargs: dict[str, Any],
        call_type: Any,
        anthropic_messages_call_type: Any,
    ) -> dict[str, Any]:
        """在 LiteLLM 选中 deployment 后清理 DeepSeek 请求参数。

        Args:
            kwargs: LiteLLM 已合并部署配置后、即将传给上游 provider 的请求参数。
            call_type: 当前调用类型。
            anthropic_messages_call_type: Anthropic messages 调用类型常量。

        Returns:
            清理后的 LiteLLM 请求参数。
        """
        if not self.should_sanitize_anthropic_messages(
            kwargs,
            call_type,
            anthropic_messages_call_type,
        ):
            return kwargs

        diagnostics = sanitize_request_context(kwargs)
        log_sanitized_context(kwargs, "async_pre_call_deployment_hook", diagnostics)
        return kwargs

    def log_pre_api_call(self, model: str, messages: list, kwargs: dict) -> AdapterResult:
        """在 LiteLLM 即将发送 HTTP 请求前兜底清理 DeepSeek 请求体。

        Args:
            model: LiteLLM 记录的当前模型名。
            messages: LiteLLM 记录的原始消息列表。
            kwargs: LiteLLM 模型调用上下文，包含即将序列化的完整请求体引用。

        Returns:
            adapter 执行结果；未命中时 changed 为 False。
        """
        if not is_deepseek_anthropic_request(kwargs):
            return AdapterResult(self.name, "log_pre_api_call")

        request_body = complete_input_dict(kwargs)
        if request_body is None:
            return AdapterResult(self.name, "log_pre_api_call")

        diagnostics = sanitize_request_context(kwargs)
        log_sanitized_context(kwargs, "log_pre_api_call", diagnostics)
        return AdapterResult(
            self.name,
            "log_pre_api_call",
            changed=True,
            diagnostics=diagnostics,
        )
