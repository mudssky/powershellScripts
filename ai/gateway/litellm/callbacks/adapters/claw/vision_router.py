"""claw 视觉请求路由 adapter。"""

import logging
from dataclasses import dataclass
from typing import Any

from callbacks.framework.adapters import GatewayCallbackAdapter

LOGGER = logging.getLogger("ClawVisionRouterAdapter")
DEFAULT_VISION_FALLBACKS = {
    "claw-plan": "mimo-v2.5",
}
IMAGE_CONTENT_TYPES = {"image_url", "input_image"}


@dataclass(frozen=True)
class ClawVisionRouterConfig:
    """claw 视觉路由配置。

    Args:
        enabled: 是否启用 adapter。
        model_fallbacks: 不支持视觉的 claw 入口到视觉模型入口的映射。

    Returns:
        数据类实例，无额外返回。
    """

    enabled: bool = True
    model_fallbacks: dict[str, str] | None = None


class ClawVisionRouterAdapter(GatewayCallbackAdapter):
    """在 Router 选 deployment 前把 claw 图片请求切到视觉模型。"""

    name = "claw_vision_router"

    def __init__(self, config: ClawVisionRouterConfig | None = None) -> None:
        """初始化 claw 视觉路由 adapter。

        Args:
            config: adapter 配置；为空时使用默认映射。

        Returns:
            无返回值。
        """
        resolved_config = config or ClawVisionRouterConfig()
        super().__init__(enabled=resolved_config.enabled, fail_open=True)
        self.config = resolved_config

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict[str, Any],
        call_type: Any,
    ) -> dict[str, Any]:
        """在请求进入 Router 前把带图片的 claw-plan 改写到视觉模型。

        Args:
            user_api_key_dict: LiteLLM 认证后的 key 上下文。
            cache: LiteLLM proxy cache 对象。
            data: LiteLLM 即将路由的请求数据。
            call_type: 当前调用类型。

        Returns:
            可能被改写 `model` 的请求数据。
        """
        model = data.get("model")
        if not isinstance(model, str):
            return data

        fallback_model = self.model_fallbacks.get(model)
        if fallback_model is None or not request_contains_image(data):
            return data

        data["model"] = fallback_model
        LOGGER.warning(
            "claw vision route switched | %s",
            {
                "stage": "async_pre_call_hook",
                "model": model,
                "fallback_model": fallback_model,
            },
        )
        return data

    @property
    def model_fallbacks(self) -> dict[str, str]:
        """读取 claw 视觉路由映射。

        Args:
            None.

        Returns:
            不支持视觉的模型到视觉模型的映射字典。
        """
        return self.config.model_fallbacks or DEFAULT_VISION_FALLBACKS


def request_contains_image(data: dict[str, Any]) -> bool:
    """判断 LiteLLM 请求结构中是否包含图片输入。

    Args:
        data: LiteLLM pre-call 请求数据。

    Returns:
        任意消息 content 中包含图片块时返回 True，否则返回 False。
    """
    messages = data.get("messages")
    if not isinstance(messages, list):
        return False

    return any(_content_contains_image(message.get("content")) for message in messages if isinstance(message, dict))


def _content_contains_image(content: Any) -> bool:
    """递归判断 content 结构中是否包含图片块。

    Args:
        content: OpenAI 兼容消息 content，可以是字符串、字典或列表。

    Returns:
        命中 `image_url` / `input_image` 图片块时返回 True，否则返回 False。
    """
    if isinstance(content, list):
        return any(_content_contains_image(item) for item in content)

    if not isinstance(content, dict):
        return False

    content_type = content.get("type")
    if isinstance(content_type, str) and content_type in IMAGE_CONTENT_TYPES:
        return True

    return any(_content_contains_image(value) for value in content.values())
