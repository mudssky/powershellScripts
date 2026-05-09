"""DeepSeek Anthropic thinking 清理核心逻辑。"""

from typing import Any

THINKING_BLOCK_TYPES = {"thinking", "redacted_thinking"}
THINKING_FIELD_KEYS = {"redacted_thinking", "thinking_blocks"}
REASONING_EFFORT_KEY = "reasoning_effort"
REQUEST_CONTENT_KEYS = {"messages", "content"}
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
    """扫描请求结构中残留的 thinking 相关路径。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。

    Returns:
        thinking 块或字段的结构路径列表，不包含正文内容。
    """
    return _thinking_paths(value, path, set())


def _thinking_paths(value: Any, path: str, seen: set[int]) -> list[str]:
    """递归扫描 thinking 路径并避免异常结构拖垮日志回调。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。
        seen: 已访问容器对象 ID 集合，用于防止循环引用。

    Returns:
        thinking 块或字段的结构路径列表。
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

    paths = [path] if _is_thinking_block(value) else []
    for key, child in value.items():
        if key in THINKING_FIELD_KEYS:
            paths.append(f"{path}.{key}")
        paths.extend(_thinking_paths(child, f"{path}.{key}", seen))
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
    before_reasoning_effort = kwargs.get("reasoning_effort")
    before_paths = thinking_paths(_diagnostic_view(kwargs, request_body))
    before_effort_paths = _reasoning_effort_paths(_diagnostic_view(kwargs, request_body))

    _sanitize_request_data(kwargs)
    if request_body is not None:
        _sanitize_request_data(request_body)

    after_paths = thinking_paths(_diagnostic_view(kwargs, request_body))
    after_effort_paths = _reasoning_effort_paths(_diagnostic_view(kwargs, request_body))
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
        "had_reasoning_effort": before_reasoning_effort is not None,
        "removed_reasoning_effort_paths": len(before_effort_paths),
        "remaining_reasoning_effort_paths": after_effort_paths[:20],
        "removed_thinking_paths": len(before_paths),
        "remaining_thinking_paths": after_paths[:20],
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
        "optional_params": kwargs.get("optional_params"),
        "extra_body": kwargs.get("extra_body"),
        "top_level_thinking": kwargs.get("thinking"),
        "reasoning_effort": kwargs.get("reasoning_effort"),
    }


def _sanitize_request_data(data: dict[str, Any]) -> None:
    """原地清理 DeepSeek Anthropic 请求参数。

    Args:
        data: LiteLLM 请求参数或完整请求体。

    Returns:
        无返回值；函数会原地修改 data。
    """
    _drop_reasoning_effort_fields(data)
    # 顶层 thinking 置为 disabled，避免 DeepSeek 进入完整历史 thinking 校验模式。
    data["thinking"] = {"type": "disabled"}
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
    if _is_thinking_block(value):
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


def _drop_reasoning_effort_fields(value: Any, seen: set[int] | None = None) -> None:
    """递归移除会与 DeepSeek `thinking: disabled` 冲突的 reasoning_effort。

    Args:
        value: 待清理的任意请求结构。
        seen: 已访问容器对象 ID 集合，用于防止循环引用。

    Returns:
        无返回值；函数会原地修改字典结构。
    """
    if seen is None:
        seen = set()
    if isinstance(value, list):
        if _seen_container(value, seen):
            return
        for item in value:
            _drop_reasoning_effort_fields(item, seen)
        return
    if not isinstance(value, dict):
        return
    if _seen_container(value, seen):
        return

    value.pop(REASONING_EFFORT_KEY, None)
    for key, child in value.items():
        # reasoning_effort 是请求参数，不是消息正文；跳过正文可避免误删工具结果里的同名业务字段。
        if key in REQUEST_CONTENT_KEYS:
            continue
        _drop_reasoning_effort_fields(child, seen)


def _reasoning_effort_paths(value: Any, path: str = "$") -> list[str]:
    """扫描请求参数结构中残留的 reasoning_effort 路径。

    Args:
        value: 待扫描的任意请求结构。
        path: 当前结构路径，用于日志定位。

    Returns:
        reasoning_effort 参数路径列表，不包含字段值。
    """
    return _field_paths(value, REASONING_EFFORT_KEY, path, set())


def _field_paths(value: Any, target_key: str, path: str, seen: set[int]) -> list[str]:
    """扫描字典树中的指定字段路径。

    Args:
        value: 待扫描的任意结构。
        target_key: 需要定位的字段名。
        path: 当前结构路径。
        seen: 已访问容器对象 ID 集合，用于防止循环引用。

    Returns:
        命中字段的结构路径列表。
    """
    if isinstance(value, list):
        if _seen_container(value, seen):
            return []
        return [
            child_path
            for index, child in enumerate(value)
            for child_path in _field_paths(child, target_key, f"{path}[{index}]", seen)
        ]
    if not isinstance(value, dict):
        return []
    if _seen_container(value, seen):
        return []

    paths = [f"{path}.{target_key}"] if value.get(target_key) is not None else []
    for key, child in value.items():
        if key in REQUEST_CONTENT_KEYS:
            continue
        paths.extend(_field_paths(child, target_key, f"{path}.{key}", seen))
    return paths


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
