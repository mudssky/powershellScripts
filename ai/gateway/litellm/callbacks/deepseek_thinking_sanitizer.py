"""LiteLLM DeepSeek 兜底请求清洗回调。"""

from typing import Any

from litellm.integrations.custom_logger import CustomLogger
from litellm.types.utils import CallTypes

from callbacks.deepseek_thinking_sanitizer_logging import log_sanitized_context
from callbacks.deepseek_thinking_sanitizer_core import (
    complete_input_dict,
    is_deepseek_anthropic_request,
    sanitize_request_context,
)


class DeepSeekThinkingSanitizer(CustomLogger):
    """在 DeepSeek Anthropic 兜底请求发出前移除不兼容的 thinking 历史。"""

    async def async_pre_call_deployment_hook(
        self,
        kwargs: dict[str, Any],
        call_type: CallTypes | None,
    ) -> dict[str, Any]:
        """在 LiteLLM 选中具体部署后清理 DeepSeek fallback 请求参数。

        Args:
            kwargs: LiteLLM 已合并部署配置后、即将传给上游 provider 的请求参数。
            call_type: 当前调用类型；这里只处理 Anthropic messages 透传请求。

        Returns:
            清理后的 LiteLLM 请求参数。
        """
        if call_type != CallTypes.anthropic_messages:
            return kwargs
        if not is_deepseek_anthropic_request(kwargs):
            return kwargs

        diagnostics = sanitize_request_context(kwargs)
        log_sanitized_context(kwargs, "async_pre_call_deployment_hook", diagnostics)
        return kwargs

    def log_pre_api_call(self, model: str, messages: list, kwargs: dict) -> None:
        """在 LiteLLM 即将发送 HTTP 请求前清理 DeepSeek fallback 请求体。

        Args:
            model: LiteLLM 记录的当前模型名。
            messages: LiteLLM 记录的原始消息列表。
            kwargs: LiteLLM 模型调用上下文，包含即将序列化的完整请求体引用。

        Returns:
            无返回值；函数会原地修改 DeepSeek Anthropic 请求体。
        """
        if not is_deepseek_anthropic_request(kwargs):
            return

        request_body = complete_input_dict(kwargs)
        if request_body is None:
            return

        diagnostics = sanitize_request_context(kwargs)
        log_sanitized_context(kwargs, "log_pre_api_call", diagnostics)


proxy_handler_instance = DeepSeekThinkingSanitizer()
