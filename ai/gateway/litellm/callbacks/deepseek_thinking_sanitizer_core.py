"""DeepSeek Anthropic thinking 清理核心逻辑。"""

from typing import Any

THINKING_BLOCK_TYPES = {"thinking", "redacted_thinking"}
THINKING_FIELD_KEYS = {"redacted_thinking", "thinking_blocks"}
_DROP = object()


def is_deepseek_anthropic_request(kwargs: dict[str, Any]) -> bool:
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
    models = [
        request_model,
        kwargs.get("model"),
        metadata.get("deployment"),
        metadata.get("deployment_model_name"),
    ]
    api_bases = [additional_args.get("api_base"), metadata.get("api_base")]
    return any(_is_deepseek_model(model) for model in models) or any(
        _is_deepseek_anthropic_base(api_base) for api_base in api_bases
    )


def complete_input_dict(kwargs: dict[str, Any]) -> dict[str, Any] | None:
    """读取 LiteLLM logging/pre-call 上下文里的完整请求体。

    Args:
        kwargs: LiteLLM hook 传入的模型调用上下文。

    Returns:
        找到完整请求体字典时返回该字典，否则返回 None。
    """
    request_body = (kwargs.get("additional_args") or {}).get("complete_input_dict")
    return request_body if isinstance(request_body, dict) else None


def thinking_paths(value: Any, path: str = "$") -> list[str]:
    """扫描请求结构中不兼容、会被清理的 thinking 相关路径。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。

    Returns:
        不兼容 thinking 块或字段的结构路径列表，不包含正文内容。
    """
    return _thinking_paths(value, path, set())


def _thinking_paths(value: Any, path: str, seen: set[int]) -> list[str]:
    """递归扫描不兼容 thinking 路径并避免异常结构拖垮日志回调。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。
        seen: 已访问容器对象 ID 集合，用于防止循环引用。

    Returns:
        不兼容 thinking 块或字段的结构路径列表。
    """
    if isinstance(value, list):
        if _seen_container(value, seen):
            return []
        return [
            child_path
            for index, child in enumerate(value)
            for child_path in _thinking_paths(child, f"{path}[{index}]", seen)
        ]
    if not isinstance(value, dict):
        return []
    if _seen_container(value, seen):
        return []

    paths = [path] if _is_incompatible_thinking_block(value) else []
    for key, child in value.items():
        if key in THINKING_FIELD_KEYS:
            paths.append(f"{path}.{key}")
        paths.extend(_thinking_paths(child, f"{path}.{key}", seen))
    return paths


def preserved_thinking_paths(value: Any, path: str = "$") -> list[str]:
    """扫描请求结构中可安全回传给上游的 thinking 块路径。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。

    Returns:
        带签名或不透明数据的 thinking 块路径列表，不包含正文内容。
    """
    return _preserved_thinking_paths(value, path, set())


def _preserved_thinking_paths(value: Any, path: str, seen: set[int]) -> list[str]:
    """递归扫描可回传 thinking 路径并避免循环引用。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。
        seen: 已访问容器对象 ID 集合，用于防止循环引用。

    Returns:
        可回传 thinking 块的结构路径列表。
    """
    if isinstance(value, list):
        if _seen_container(value, seen):
            return []
        return [
            child_path
            for index, child in enumerate(value)
            for child_path in _preserved_thinking_paths(child, f"{path}[{index}]", seen)
        ]
    if not isinstance(value, dict):
        return []
    if _seen_container(value, seen):
        return []

    paths = [path] if _is_preservable_thinking_block(value) else []
    for key, child in value.items():
        paths.extend(_preserved_thinking_paths(child, f"{path}.{key}", seen))
    return paths


def sanitize_request_context(kwargs: dict[str, Any]) -> dict[str, Any]:
    """清理 LiteLLM hook 上下文里所有会流向 DeepSeek 的请求副本。

    Args:
        kwargs: LiteLLM hook 传入的请求上下文字典。

    Returns:
        不含正文内容的结构诊断字段，可直接用于日志输出。
    """
    request_body = complete_input_dict(kwargs)
    before_thinking = kwargs.get("thinking")
    before_view = _diagnostic_view(kwargs, request_body)
    before_paths = thinking_paths(before_view)
    before_preserved_paths = preserved_thinking_paths(before_view)

    _sanitize_request_data(kwargs)
    if request_body is not None:
        _sanitize_request_data(request_body)

    after_view = _diagnostic_view(kwargs, request_body)
    after_paths = thinking_paths(after_view)
    after_preserved_paths = preserved_thinking_paths(after_view)
    return {
        "messages_count": len(kwargs.get("messages") or [])
        if isinstance(kwargs.get("messages"), list)
        else None,
        "top_level_thinking_before": before_thinking.get("type")
        if isinstance(before_thinking, dict)
        else None,
        "top_level_thinking_after": kwargs.get("thinking", {}).get("type")
        if isinstance(kwargs.get("thinking"), dict)
        else None,
        "removed_thinking_paths": len(before_paths),
        "remaining_thinking_paths": after_paths[:20],
        "preserved_thinking_paths": after_preserved_paths[:20],
        "preserved_thinking_blocks_before": len(before_preserved_paths),
        "preserved_thinking_blocks_after": len(after_preserved_paths),
    }


def _is_deepseek_model(model: Any) -> bool:
    """判断模型名是否匹配 DeepSeek 兜底模型。

    Args:
        model: 任意模型名。

    Returns:
        匹配 DeepSeek 兜底模型时返回 True，否则返回 False。
    """
    model_name = str(model or "").removeprefix("anthropic/")
    return model_name.startswith(("deepseek-v4-pro", "deepseek-v4-flash")) or (
        "claude-code-deepseek-" in model_name
    )


def _is_deepseek_anthropic_base(api_base: Any) -> bool:
    """判断上游地址是否为 DeepSeek Anthropic 兼容地址。

    Args:
        api_base: LiteLLM 解析出的上游地址。

    Returns:
        命中 DeepSeek Anthropic 地址时返回 True，否则返回 False。
    """
    normalized = str(api_base or "").lower()
    return "deepseek" in normalized and "/anthropic" in normalized


def _diagnostic_view(
    kwargs: dict[str, Any],
    request_body: dict[str, Any] | None,
) -> dict[str, Any]:
    """构造不含密钥和 headers 的诊断视图。

    Args:
        kwargs: LiteLLM hook 传入的请求上下文。
        request_body: LiteLLM 已构造的完整请求体。

    Returns:
        只包含消息与推理参数的诊断视图。
    """
    return {
        "messages": kwargs.get("messages"),
        "complete_input_dict": request_body,
        "top_level_thinking": kwargs.get("thinking"),
    }


def _sanitize_request_data(data: dict[str, Any]) -> None:
    """原地清理 DeepSeek Anthropic 请求参数。

    Args:
        data: LiteLLM 请求参数或完整请求体。

    Returns:
        无返回值；函数会原地修改 data。
    """
    messages = data.get("messages")
    if isinstance(messages, list):
        messages[:] = [_sanitize_message(message) for message in messages]
        messages[:] = [message for message in messages if message is not _DROP]


def _sanitize_message(message: Any) -> Any:
    """清理单条历史消息里的 thinking 数据。

    Args:
        message: Anthropic messages 列表中的单条消息。

    Returns:
        清理后的消息；返回内部哨兵值时表示该消息应被删除。
    """
    if not isinstance(message, dict):
        return message

    sanitized_message = dict(message)
    sanitized_message.pop("thinking_blocks", None)
    content = _sanitize_value(sanitized_message.get("content"))
    if isinstance(content, list) and len(content) == 0:
        if sanitized_message.get("role") == "assistant":
            return _DROP
        content = ""
    sanitized_message["content"] = [] if content is _DROP else content
    return sanitized_message


def _sanitize_value(value: Any) -> Any:
    """递归清理嵌套 content 中的 thinking 块。

    Args:
        value: 任意嵌套字段值。

    Returns:
        清理后的值；返回内部哨兵值时表示当前列表元素应被删除。
    """
    if isinstance(value, list):
        return [
            sanitized
            for item in value
            if (sanitized := _sanitize_value(item)) is not _DROP
        ]
    if not isinstance(value, dict):
        return value
    if _is_preservable_thinking_block(value):
        return value
    if _is_incompatible_thinking_block(value):
        return _DROP
    return {
        key: sanitized
        for key, child in value.items()
        if key not in {"thinking", *THINKING_FIELD_KEYS}
        if (sanitized := _sanitize_value(child)) is not _DROP
    }


def _is_thinking_block(value: dict[str, Any]) -> bool:
    """判断字典是否为 Anthropic thinking content block。

    Args:
        value: Anthropic content block 或其它字典结构。

    Returns:
        `type` 是字符串且命中 thinking 类型时返回 True，否则返回 False。
    """
    block_type = value.get("type")
    return isinstance(block_type, str) and block_type in THINKING_BLOCK_TYPES


def _is_incompatible_thinking_block(value: dict[str, Any]) -> bool:
    """判断字典是否为不能安全回传给 DeepSeek 的 thinking 内容块。

    Args:
        value: Anthropic content block 或其它字典结构。

    Returns:
        thinking 块缺少可校验签名或不透明数据时返回 True，否则返回 False。
    """
    return _is_thinking_block(value) and not _is_preservable_thinking_block(value)


def _is_preservable_thinking_block(value: dict[str, Any]) -> bool:
    """判断 thinking 内容块是否应原样回传给 DeepSeek。

    Args:
        value: Anthropic content block 或其它字典结构。

    Returns:
        带非空 `signature` 的 thinking 块，或带非空 `data` 的 redacted_thinking
        块返回 True；其它结构返回 False。
    """
    block_type = value.get("type")
    if block_type == "thinking":
        return _has_non_empty_string(value.get("signature"))
    if block_type == "redacted_thinking":
        return _has_non_empty_string(value.get("data"))
    return False


def _has_non_empty_string(value: Any) -> bool:
    """判断字段是否为非空字符串。

    Args:
        value: 任意字段值。

    Returns:
        字段是去除空白后仍非空的字符串时返回 True，否则返回 False。
    """
    return isinstance(value, str) and value.strip() != ""


def _seen_container(value: Any, seen: set[int]) -> bool:
    """记录容器对象访问状态，避免诊断遍历或清理遇到循环引用。

    Args:
        value: 当前容器对象。
        seen: 已访问容器对象 ID 集合。

    Returns:
        当前容器已经访问过时返回 True，否则记录后返回 False。
    """
    value_id = id(value)
    if value_id in seen:
        return True
    seen.add(value_id)
    return False
