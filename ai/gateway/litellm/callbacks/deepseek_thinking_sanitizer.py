"""LiteLLM DeepSeek 兜底请求清洗回调。"""

import logging
import os
from typing import Any

from litellm.integrations.custom_logger import CustomLogger
from litellm.types.utils import CallTypes

DEEPSEEK_MODEL_PREFIXES = ("deepseek-v4-pro", "deepseek-v4-flash")
THINKING_BLOCK_TYPES = {"thinking", "redacted_thinking"}
SANITIZER_LOGGER_NAME = "DeepSeekThinkingSanitizer"

LOGGER = logging.getLogger(SANITIZER_LOGGER_NAME)
_DROP = object()


def _debug_enabled() -> bool:
    """判断是否启用 DeepSeek sanitizer 结构诊断日志。

    Args:
        None.

    Returns:
        环境变量显式关闭时返回 False，否则返回 True。
    """
    return os.getenv("DEEPSEEK_THINKING_SANITIZER_DEBUG", "1").lower() not in {
        "0",
        "false",
        "off",
    }


def _debug_log(message: str, **fields: Any) -> None:
    """输出不包含正文内容的 sanitizer 结构诊断日志。

    Args:
        message: 日志事件名称。
        **fields: 可安全输出的结构字段，不应包含 prompt 正文或密钥。

    Returns:
        无返回值。
    """
    if not _debug_enabled():
        return
    LOGGER.warning("%s | %s", message, fields)


def _is_deepseek_model_name(model: Any) -> bool:
    """判断模型名是否指向 DeepSeek Claude Code 兜底模型。

    Args:
        model: LiteLLM 对外模型名、部署模型名或上游请求体中的模型名。

    Returns:
        命中 DeepSeek 兜底模型时返回 True，否则返回 False。
    """
    model_name = str(model or "")
    if model_name.startswith("anthropic/"):
        model_name = model_name.removeprefix("anthropic/")
    return (
        model_name.startswith(DEEPSEEK_MODEL_PREFIXES)
        or "claude-code-deepseek-" in model_name
    )


def _is_deepseek_anthropic_api_base(api_base: Any) -> bool:
    """判断上游地址是否是 DeepSeek Anthropic 兼容端点。

    Args:
        api_base: LiteLLM 解析出的上游基础地址或完整请求地址。

    Returns:
        命中 DeepSeek Anthropic 地址时返回 True，否则返回 False。
    """
    normalized_api_base = str(api_base or "").lower()
    return "deepseek" in normalized_api_base and "/anthropic" in normalized_api_base


def _is_deepseek_anthropic_request(kwargs: dict[str, Any]) -> bool:
    """判断当前请求是否即将发往 DeepSeek Anthropic 兼容端点。

    Args:
        kwargs: LiteLLM 传入的模型调用上下文。

    Returns:
        命中 DeepSeek Anthropic 请求时返回 True，否则返回 False。
    """
    additional_args = kwargs.get("additional_args") or {}
    request_body = additional_args.get("complete_input_dict")
    request_model = request_body.get("model") if isinstance(request_body, dict) else None
    metadata = kwargs.get("litellm_metadata") or kwargs.get("metadata") or {}

    return (
        _is_deepseek_model_name(request_model)
        or _is_deepseek_model_name(kwargs.get("model"))
        or _is_deepseek_model_name(metadata.get("deployment"))
        or _is_deepseek_model_name(metadata.get("deployment_model_name"))
        or _is_deepseek_anthropic_api_base(additional_args.get("api_base"))
        or _is_deepseek_anthropic_api_base(metadata.get("api_base"))
    )


def _find_thinking_paths(value: Any, path: str = "$") -> list[str]:
    """扫描请求结构中残留的 thinking 相关路径。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。

    Returns:
        thinking 块或字段的结构路径列表，不包含正文内容。
    """
    paths: list[str] = []
    if isinstance(value, dict):
        block_type = value.get("type")
        if block_type in THINKING_BLOCK_TYPES:
            paths.append(path)
        for key, child in value.items():
            if key in {"redacted_thinking", "thinking_blocks"}:
                paths.append(f"{path}.{key}")
            paths.extend(_find_thinking_paths(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            paths.extend(_find_thinking_paths(child, f"{path}[{index}]"))
    return paths


def _sanitize_nested_value(value: Any) -> Any:
    """递归清理 Anthropic 请求结构中 DeepSeek 无法校验的 thinking 数据。

    Args:
        value: 任意嵌套的请求字段值。

    Returns:
        清理后的值；返回内部哨兵值时表示当前列表元素应被删除。
    """
    if isinstance(value, list):
        sanitized_items: list[Any] = []
        for item in value:
            sanitized_item = _sanitize_nested_value(item)
            if sanitized_item is not _DROP:
                sanitized_items.append(sanitized_item)
        return sanitized_items

    if not isinstance(value, dict):
        return value

    if value.get("type") in THINKING_BLOCK_TYPES:
        return _DROP

    sanitized_dict: dict[str, Any] = {}
    for key, child in value.items():
        if key in {"thinking", "redacted_thinking", "thinking_blocks"}:
            continue
        sanitized_child = _sanitize_nested_value(child)
        if sanitized_child is not _DROP:
            sanitized_dict[key] = sanitized_child

    return sanitized_dict


def _replace_list_in_place(target: list[Any], source: list[Any]) -> None:
    """用切片替换保持列表对象引用不变。

    Args:
        target: LiteLLM 后续仍会引用的原列表。
        source: 已清理的新列表内容。

    Returns:
        无返回值；函数会原地修改 target。
    """
    target[:] = source


def _sanitize_content(content: Any) -> Any:
    """清理单条 Anthropic message 的 content 字段。

    Args:
        content: 单条消息的 content 字段。

    Returns:
        清理后的 content，列表内容会被递归清理。
    """
    sanitized_content = _sanitize_nested_value(content)
    if sanitized_content is _DROP:
        return []
    return sanitized_content


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
        sanitized_content = _sanitize_content(sanitized_message.get("content"))
        if isinstance(sanitized_content, list) and len(sanitized_content) == 0:
            # thinking-only 历史消息对 DeepSeek 兜底没有可见上下文价值，
            # 保留空内容反而可能触发上游校验失败。
            if sanitized_message.get("role") == "assistant":
                continue
            sanitized_message["content"] = ""
        else:
            sanitized_message["content"] = sanitized_content

        sanitized_messages.append(sanitized_message)

    _replace_list_in_place(messages, sanitized_messages)
    return messages


def _sanitize_request_data(data: dict[str, Any]) -> dict[str, Any]:
    """清理 LiteLLM 请求参数中的 DeepSeek 不兼容 thinking 字段。

    Args:
        data: LiteLLM 即将传给上游部署的请求参数。

    Returns:
        原地清理后的请求参数。
    """
    data.pop("thinking", None)
    data.pop("reasoning_effort", None)
    # 顶层 thinking 置为 disabled，确保 DeepSeek Anthropic 端点不会进入
    # 需要完整历史 thinking 回传的校验模式。
    data["thinking"] = {"type": "disabled"}
    messages = data.get("messages")
    data["messages"] = _sanitize_messages(messages)
    return data


def _sanitize_request_context(kwargs: dict[str, Any], stage: str) -> dict[str, Any]:
    """清理 LiteLLM hook 上下文里所有会流向 DeepSeek 的请求副本。

    Args:
        kwargs: LiteLLM hook 传入的请求上下文字典。
        stage: 当前 hook 阶段名称，用于诊断日志。

    Returns:
        原地清理后的 hook 上下文。
    """
    before_thinking = kwargs.get("thinking")
    before_reasoning_effort = kwargs.get("reasoning_effort")
    before_paths = _find_thinking_paths(
        {
            "messages": kwargs.get("messages"),
            "complete_input_dict": (kwargs.get("additional_args") or {}).get(
                "complete_input_dict"
            ),
            "top_level_thinking": before_thinking,
            "reasoning_effort": before_reasoning_effort,
        }
    )

    _sanitize_request_data(kwargs)

    additional_args = kwargs.get("additional_args") or {}
    request_body = additional_args.get("complete_input_dict")
    if isinstance(request_body, dict):
        _sanitize_request_data(request_body)

    after_paths = _find_thinking_paths(
        {
            "messages": kwargs.get("messages"),
            "complete_input_dict": request_body,
            "top_level_thinking": kwargs.get("thinking"),
            "reasoning_effort": kwargs.get("reasoning_effort"),
        }
    )
    metadata = kwargs.get("litellm_metadata") or kwargs.get("metadata") or {}
    _debug_log(
        "deepseek thinking sanitized",
        stage=stage,
        model=kwargs.get("model"),
        deployment=metadata.get("deployment"),
        deployment_model_name=metadata.get("deployment_model_name"),
        api_base=additional_args.get("api_base") or metadata.get("api_base"),
        messages_count=len(kwargs.get("messages") or [])
        if isinstance(kwargs.get("messages"), list)
        else None,
        top_level_thinking_before=before_thinking.get("type")
        if isinstance(before_thinking, dict)
        else None,
        top_level_thinking_after=kwargs.get("thinking", {}).get("type")
        if isinstance(kwargs.get("thinking"), dict)
        else None,
        had_reasoning_effort=before_reasoning_effort is not None,
        removed_thinking_paths=len(before_paths),
        remaining_thinking_paths=after_paths[:20],
    )
    return kwargs


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
        if not _is_deepseek_anthropic_request(kwargs):
            return kwargs
        return _sanitize_request_context(kwargs, "async_pre_call_deployment_hook")

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

        _sanitize_request_data(request_body)

        # 同步 LiteLLM 日志上下文，避免清理后的请求体和日志里的顶层字段不一致。
        _sanitize_request_context(kwargs, "log_pre_api_call")


proxy_handler_instance = DeepSeekThinkingSanitizer()
