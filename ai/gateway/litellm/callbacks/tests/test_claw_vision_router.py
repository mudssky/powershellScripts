"""claw 视觉路由 adapter 回归测试。"""

import asyncio
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from callbacks.adapters.claw.vision_router import (  # noqa: E402
    ClawVisionRouterAdapter,
    ClawVisionRouterConfig,
    request_contains_image,
)


def _run(coro: Any) -> Any:
    """执行异步测试协程。

    Args:
        coro: 待执行的协程对象。

    Returns:
        协程返回值。
    """
    return asyncio.run(coro)


def _image_request(model: str = "claw-plan") -> dict[str, Any]:
    """构造最小图片请求。

    Args:
        model: 请求中的 LiteLLM model group 名称。

    Returns:
        OpenAI chat completions 风格请求字典。
    """
    return {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "描述图片"},
                    {
                        "type": "image_url",
                        "image_url": {"url": "https://example.com/image.png"},
                    },
                ],
            }
        ],
    }


def main() -> None:
    """执行 claw 视觉路由 adapter 回归断言。

    Args:
        None.

    Returns:
        无返回值；断言失败时抛出异常。
    """
    assert request_contains_image(_image_request())
    assert not request_contains_image(
        {
            "model": "claw-plan",
            "messages": [{"role": "user", "content": "只包含文本"}],
        }
    )

    adapter = ClawVisionRouterAdapter()
    data = _image_request()
    routed = _run(adapter.async_pre_call_hook(None, None, data, "completion"))
    assert routed is data
    assert routed["model"] == "mimo-v2.5"

    text_data = {
        "model": "claw-plan",
        "messages": [{"role": "user", "content": "你好"}],
    }
    routed = _run(adapter.async_pre_call_hook(None, None, text_data, "completion"))
    assert routed["model"] == "claw-plan"

    explicit_glm = _image_request("claw-glmplan-5.1")
    routed = _run(adapter.async_pre_call_hook(None, None, explicit_glm, "completion"))
    assert routed["model"] == "claw-glmplan-5.1"

    custom = ClawVisionRouterAdapter(
        ClawVisionRouterConfig(model_fallbacks={"claw-glmplan-5.1": "mimo-v2.5"})
    )
    routed = _run(custom.async_pre_call_hook(None, None, explicit_glm, "completion"))
    assert routed["model"] == "mimo-v2.5"

    print("claw vision router ok")


if __name__ == "__main__":
    main()
