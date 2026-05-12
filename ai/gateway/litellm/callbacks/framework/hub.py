"""LiteLLM 网关统一 callback hub。"""

import logging
from typing import Any

try:
    from litellm.integrations.custom_logger import CustomLogger
    from litellm.types.utils import CallTypes
except ModuleNotFoundError:

    class CustomLogger:  # type: ignore[no-redef]
        """本地测试用 LiteLLM CustomLogger 兼容基类。"""

    class CallTypes:  # type: ignore[no-redef]
        """本地测试用 LiteLLM 调用类型常量。"""

        anthropic_messages = "anthropic_messages"


from callbacks.adapters.deepseek.thinking_sanitizer import (
    DeepSeekThinkingSanitizerAdapter,
)
from callbacks.adapters.glm.cooldown import GlmCooldownAdapter
from callbacks.framework.adapters import GatewayCallbackAdapter

LOGGER = logging.getLogger("GatewayCallbackHub")


class GatewayCallbackHub(CustomLogger):
    """将 LiteLLM callback 生命周期分发给多个 adapter。"""

    def __init__(self, adapters: list[GatewayCallbackAdapter] | None = None) -> None:
        """初始化 callback hub。

        Args:
            adapters: 可选 adapter 列表；为空时使用默认注册表。

        Returns:
            无返回值。
        """
        self.adapters = adapters or default_adapters()

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict[str, Any],
        call_type: Any,
    ) -> dict[str, Any]:
        """在 LiteLLM Proxy 请求进入 Router 前分发请求前 hook。

        Args:
            user_api_key_dict: LiteLLM 认证后的 key 上下文。
            cache: LiteLLM proxy cache 对象。
            data: LiteLLM 即将路由的请求数据。
            call_type: 当前调用类型。

        Returns:
            可能被 adapter 改写后的请求数据。
        """
        for adapter in self._enabled_adapters():
            hook = getattr(adapter, "async_pre_call_hook", None)
            if hook is None:
                continue
            data = await self._run_async_hook(
                adapter,
                "async_pre_call_hook",
                hook,
                user_api_key_dict,
                cache,
                data,
                call_type,
                default=data,
            )
        return data

    async def async_pre_call_deployment_hook(
        self,
        kwargs: dict[str, Any],
        call_type: Any,
    ) -> dict[str, Any]:
        """在 LiteLLM 选中 deployment 后分发请求改写 hook。

        Args:
            kwargs: LiteLLM 已合并部署配置后的请求参数。
            call_type: 当前调用类型。

        Returns:
            可能被 adapter 改写后的请求参数。
        """
        for adapter in self._enabled_adapters():
            hook = getattr(adapter, "async_pre_call_deployment_hook", None)
            if hook is None:
                continue
            kwargs = await self._run_async_hook(
                adapter,
                "async_pre_call_deployment_hook",
                hook,
                kwargs,
                call_type,
                CallTypes.anthropic_messages,
                default=kwargs,
            )
        return kwargs

    async def async_log_failure_event(
        self,
        kwargs: dict[str, Any],
        response_obj: Any,
        start_time: Any,
        end_time: Any,
    ) -> None:
        """在 LiteLLM 失败日志阶段分发失败事件 hook。

        Args:
            kwargs: LiteLLM 失败事件上下文。
            response_obj: LiteLLM 传入的异常或失败响应对象。
            start_time: 调用开始时间。
            end_time: 调用结束时间。

        Returns:
            无返回值。
        """
        for adapter in self._enabled_adapters():
            hook = getattr(adapter, "async_log_failure_event", None)
            if hook is None:
                continue
            await self._run_async_hook(
                adapter,
                "async_log_failure_event",
                hook,
                kwargs,
                response_obj,
                start_time,
                end_time,
                default=None,
            )

    def log_pre_api_call(self, model: str, messages: list, kwargs: dict) -> None:
        """在 LiteLLM 即将发送 HTTP 请求前分发同步日志 hook。

        Args:
            model: LiteLLM 记录的当前模型名。
            messages: LiteLLM 记录的原始消息列表。
            kwargs: LiteLLM 模型调用上下文。

        Returns:
            无返回值。
        """
        for adapter in self._enabled_adapters():
            hook = getattr(adapter, "log_pre_api_call", None)
            if hook is None:
                continue
            self._run_sync_hook(
                adapter,
                "log_pre_api_call",
                hook,
                model,
                messages,
                kwargs,
            )

    def _enabled_adapters(self) -> list[GatewayCallbackAdapter]:
        """读取已启用 adapter 列表。

        Args:
            None.

        Returns:
            已启用 adapter 列表。
        """
        return [adapter for adapter in self.adapters if adapter.enabled]

    async def _run_async_hook(
        self,
        adapter: GatewayCallbackAdapter,
        stage: str,
        hook: Any,
        *args: Any,
        default: Any,
    ) -> Any:
        """执行异步 adapter hook 并按 fail-open 策略隔离异常。

        Args:
            adapter: 当前 adapter。
            stage: 生命周期阶段名称。
            hook: 待执行的 hook。
            *args: hook 位置参数。
            default: fail-open 时返回的默认值。

        Returns:
            hook 返回值；fail-open 时返回 default。
        """
        try:
            result = await hook(*args)
            return default if result is None else result
        except Exception:
            self._handle_adapter_error(adapter, stage)
            return default

    def _run_sync_hook(
        self,
        adapter: GatewayCallbackAdapter,
        stage: str,
        hook: Any,
        *args: Any,
    ) -> None:
        """执行同步 adapter hook 并按 fail-open 策略隔离异常。

        Args:
            adapter: 当前 adapter。
            stage: 生命周期阶段名称。
            hook: 待执行的 hook。
            *args: hook 位置参数。

        Returns:
            无返回值。
        """
        try:
            hook(*args)
        except Exception:
            self._handle_adapter_error(adapter, stage)

    def _handle_adapter_error(
        self,
        adapter: GatewayCallbackAdapter,
        stage: str,
    ) -> None:
        """处理 adapter 异常。

        Args:
            adapter: 抛出异常的 adapter。
            stage: 生命周期阶段名称。

        Returns:
            无返回值；fail_open 为 False 时重新抛出异常。
        """
        LOGGER.exception(
            "gateway callback adapter failed | %s",
            {"adapter": adapter.name, "stage": stage, "fail_open": adapter.fail_open},
        )
        if not adapter.fail_open:
            raise


def default_adapters() -> list[GatewayCallbackAdapter]:
    """构造默认 callback adapter 列表。

    Args:
        None.

    Returns:
        默认启用的 adapter 列表。
    """
    return [
        GlmCooldownAdapter(),
        DeepSeekThinkingSanitizerAdapter(),
    ]
