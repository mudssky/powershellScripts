"""LiteLLM DeepSeek 兜底请求清洗回调。"""

from typing import Any

from litellm.integrations.custom_logger import CustomLogger

DEEPSEEK_MODEL_PREFIXES = ("deepseek-v4-pro", "deepseek-v4-flash")
THINKING_BLOCK_TYPES = {"thinking", "redacted_thinking"}


def _is_deepseek_anthropic_request(kwargs: dict[str, Any]) -> bool:
    """判断当前请求是否即将发往 DeepSeek Anthropic 兼容端点。

    Args:
        kwargs: LiteLLM 传入的模型调用上下文。

    Returns:
        命中 DeepSeek Anthropic 请求时返回 True，否则返回 False。
    """
    additional_args = kwargs.get("additional_args") or {}
    request_body = additional_args.get("complete_input_dict")
    request_model = ""
    if isinstance(request_body, dict):
        request_model = str(request_body.get("model") or "")

    api_base = str(additional_args.get("api_base") or "")
    return request_model.startswith(DEEPSEEK_MODEL_PREFIXES) or ("deepseek" in api_base and "/anthropic/" in api_base)


def _without_thinking_blocks(content: Any) -> Any:
    """移除 Anthropic content 列表里的 thinking 内容块。

    Args:
        content: 单条消息的 content 字段。

    Returns:
        清理后的 content；非列表内容会原样返回。
    """
    if not isinstance(content, list):
        return content

    return [block for block in content if not (isinstance(block, dict) and block.get("type") in THINKING_BLOCK_TYPES)]


def _sanitize_messages(messages: Any) -> Any:
    """清理历史消息中 DeepSeek 兜底无法校验的 thinking 块。

    Args:
        messages: Anthropic messages 请求体中的 messages 字段。

    Returns:
        清理后的 messages；非列表内容会原样返回。
    """
    if not isinstance(messages, list):
        return messages

    sanitized_messages: list[Any] = []
    for message in messages:
        if not isinstance(message, dict):
            sanitized_messages.append(message)
            continue

        sanitized_message = dict(message)
        sanitized_message.pop("thinking_blocks", None)
        sanitized_content = _without_thinking_blocks(sanitized_message.get("content"))
        if isinstance(sanitized_content, list) and len(sanitized_content) == 0:
            # thinking-only 历史消息对 DeepSeek 兜底没有可见上下文价值，
            # 保留空内容反而可能触发上游校验失败。
            if sanitized_message.get("role") == "assistant":
                continue
            sanitized_message["content"] = ""
        else:
            sanitized_message["content"] = sanitized_content

        sanitized_messages.append(sanitized_message)

    return sanitized_messages


class DeepSeekThinkingSanitizer(CustomLogger):
    """在 DeepSeek Anthropic 兜底请求发出前移除不兼容的 thinking 历史。"""

    def log_pre_api_call(self, model: str, messages: list, kwargs: dict) -> None:
        """在 LiteLLM 即将发送 HTTP 请求前清理 DeepSeek fallback 请求体。

        Args:
            model: LiteLLM 记录的当前模型名。
            messages: LiteLLM 记录的原始消息列表。
            kwargs: LiteLLM 模型调用上下文，包含即将序列化的完整请求体引用。

        Returns:
            无返回值；函数会原地修改 DeepSeek Anthropic 请求体。
        """
        if not _is_deepseek_anthropic_request(kwargs):
            return

        additional_args = kwargs.get("additional_args") or {}
        request_body = additional_args.get("complete_input_dict")
        if not isinstance(request_body, dict):
            return

        request_body.pop("thinking", None)
        request_body.pop("reasoning_effort", None)
        request_body["messages"] = _sanitize_messages(request_body.get("messages"))

        # 同步 LiteLLM 日志上下文，避免清理后的请求体和日志里的顶层字段不一致。
        kwargs.pop("thinking", None)
        kwargs.pop("reasoning_effort", None)
        kwargs["messages"] = request_body.get("messages")


proxy_handler_instance = DeepSeekThinkingSanitizer()
