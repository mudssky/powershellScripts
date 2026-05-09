"""DeepSeek thinking sanitizer 核心逻辑回归测试。"""

import importlib.util
from pathlib import Path
from typing import Any


def _load_core_module() -> Any:
    """从同目录加载 sanitizer core 模块。

    Args:
        None.

    Returns:
        已加载的 sanitizer core 模块对象。
    """
    module_path = Path(__file__).with_name("deepseek_thinking_sanitizer_core.py")
    spec = importlib.util.spec_from_file_location(
        "deepseek_thinking_sanitizer_core",
        module_path,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载模块: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _sample_kwargs() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """构造包含多层 thinking 历史的 LiteLLM hook 参数。

    Args:
        None.

    Returns:
        LiteLLM hook kwargs 与其中的原始 messages 列表引用。
    """
    messages = [
        {"role": "user", "content": "hi"},
        {
            "role": "assistant",
            "thinking_blocks": [{"type": "thinking", "thinking": "old"}],
            "content": [
                {"type": "thinking", "thinking": "direct"},
                {
                    "type": "thinking",
                    "thinking": "must pass back",
                    "signature": "signed-token",
                },
                {"type": "text", "text": "visible"},
                {
                    "type": "tool_result",
                    "content": [
                        {"type": "redacted_thinking", "data": "secret"},
                        {"type": "redacted_thinking", "data": ""},
                        {"type": "text", "text": "nested"},
                    ],
                },
            ],
        },
    ]
    return (
        {
            "model": "anthropic/deepseek-v4-pro[1m]",
            "messages": messages,
            "thinking": {"type": "enabled"},
            "reasoning_effort": "high",
            "optional_params": {
                "reasoning_effort": "medium",
            },
            "output_config": {"effort": "max", "format": {"type": "text"}},
            "litellm_metadata": {
                "deployment": "anthropic/deepseek-v4-pro[1m]",
                "deployment_model_name": "claude-code-deepseek-v4-pro",
                "api_base": "https://api.deepseek.com/anthropic",
            },
            "additional_args": {
                "complete_input_dict": {
                    "model": "deepseek-v4-pro[1m]",
                    "messages": messages,
                    "thinking": {"type": "enabled"},
                    "reasoning_effort": "high",
                    "output_config": {"effort": "max", "format": {"type": "text"}},
                    "extra_body": {"reasoning_effort": "low"},
                }
            },
        },
        messages,
    )


def _assert_malformed_type_is_safe(core: Any) -> None:
    """断言诊断扫描遇到非字符串 type 时不抛异常。

    Args:
        core: 已加载的 sanitizer core 模块对象。

    Returns:
        无返回值；断言失败时抛出异常。
    """
    malformed = {
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {"type": {"unexpected": "dict"}, "thinking": "not-a-block"},
                    {"type": "thinking", "thinking": "old"},
                    {
                        "type": "thinking",
                        "thinking": "signed",
                        "signature": "signed-token",
                    },
                ],
            }
        ],
    }

    assert core.thinking_paths(malformed) == ["$.messages[0].content[1]"]
    assert core.preserved_thinking_paths(malformed) == ["$.messages[0].content[2]"]


def main() -> None:
    """执行 sanitizer core 回归断言。

    Args:
        None.

    Returns:
        无返回值；断言失败时抛出异常。
    """
    core = _load_core_module()
    kwargs, messages = _sample_kwargs()
    original_messages_id = id(messages)

    assert core.is_deepseek_anthropic_request(kwargs)
    diagnostics = core.sanitize_request_context(kwargs)

    assert id(messages) == original_messages_id
    assert kwargs["messages"] is messages
    assert kwargs["thinking"] == {"type": "enabled"}
    assert kwargs["reasoning_effort"] == "high"
    assert kwargs["optional_params"]["reasoning_effort"] == "medium"
    assert kwargs["output_config"] == {"effort": "max", "format": {"type": "text"}}
    request_body = kwargs["additional_args"]["complete_input_dict"]
    assert request_body["reasoning_effort"] == "high"
    assert request_body["extra_body"]["reasoning_effort"] == "low"
    assert request_body["output_config"] == {
        "effort": "max",
        "format": {"type": "text"},
    }
    assert request_body["thinking"] == {"type": "enabled"}
    assert core.thinking_paths(kwargs) == []
    assert core.preserved_thinking_paths(kwargs) == [
        "$.messages[1].content[0]",
        "$.messages[1].content[2].content[0]",
    ]
    assert diagnostics["removed_thinking_paths"] == 4
    assert diagnostics["remaining_thinking_paths"] == []
    assert diagnostics["preserved_thinking_blocks_before"] == 2
    assert diagnostics["preserved_thinking_blocks_after"] == 2
    assert messages[1]["content"] == [
        {
            "type": "thinking",
            "thinking": "must pass back",
            "signature": "signed-token",
        },
        {"type": "text", "text": "visible"},
        {
            "type": "tool_result",
            "content": [
                {"type": "redacted_thinking", "data": "secret"},
                {"type": "text", "text": "nested"},
            ],
        },
    ]

    content_payload = {
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "reasoning_effort": "business-data",
                        "output_config": {"effort": "business-data"},
                    }
                ],
            }
        ],
        "reasoning_effort": "high",
        "output_config": {"effort": "max"},
    }
    core.sanitize_request_context(content_payload)
    assert content_payload["messages"][0]["content"][0]["reasoning_effort"] == (
        "business-data"
    )
    assert content_payload["messages"][0]["content"][0]["output_config"] == {
        "effort": "business-data"
    }
    assert content_payload["reasoning_effort"] == "high"
    assert content_payload["output_config"] == {"effort": "max"}

    _assert_malformed_type_is_safe(core)
    print("deepseek thinking sanitizer core ok")


if __name__ == "__main__":
    main()
