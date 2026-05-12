"""LiteLLM gateway callback hub 回归测试。"""

import asyncio
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from callbacks.framework.hub import GatewayCallbackHub


def _run(coro: Any) -> Any:
    """执行异步测试协程。

    Args:
        coro: 待执行的协程对象。

    Returns:
        协程返回值。
    """
    return asyncio.run(coro)


class RecordingAdapter:
    """记录 hub 生命周期分发顺序的测试 adapter。"""

    name = "recording"
    enabled = True
    fail_open = True

    def __init__(self) -> None:
        """初始化测试 adapter。

        Args:
            None.

        Returns:
            无返回值。
        """
        self.events: list[str] = []

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict[str, Any],
        call_type: Any,
    ) -> dict[str, Any]:
        """记录请求前 hook。

        Args:
            user_api_key_dict: LiteLLM key 上下文。
            cache: LiteLLM cache 对象。
            data: 请求数据。
            call_type: 调用类型。

        Returns:
            修改后的请求数据。
        """
        self.events.append("async_pre_call_hook")
        data["recorded"] = True
        return data

    async def async_pre_call_deployment_hook(
        self,
        kwargs: dict[str, Any],
        call_type: Any,
        anthropic_messages_call_type: Any,
    ) -> dict[str, Any]:
        """记录 deployment pre-call hook。

        Args:
            kwargs: 请求参数。
            call_type: 调用类型。
            anthropic_messages_call_type: Anthropic messages 调用类型常量。

        Returns:
            修改后的请求参数。
        """
        self.events.append("async_pre_call_deployment_hook")
        kwargs["deployment_recorded"] = anthropic_messages_call_type
        return kwargs

    async def async_log_failure_event(
        self,
        kwargs: dict[str, Any],
        response_obj: Any,
        start_time: Any,
        end_time: Any,
    ) -> None:
        """记录失败日志 hook。

        Args:
            kwargs: 失败上下文。
            response_obj: 失败对象。
            start_time: 开始时间。
            end_time: 结束时间。

        Returns:
            无返回值。
        """
        self.events.append("async_log_failure_event")

    def log_pre_api_call(self, model: str, messages: list, kwargs: dict) -> None:
        """记录同步 pre-api hook。

        Args:
            model: 模型名。
            messages: 消息列表。
            kwargs: 请求上下文。

        Returns:
            无返回值。
        """
        self.events.append("log_pre_api_call")


def main() -> None:
    """执行 gateway callback hub 回归断言。

    Args:
        None.

    Returns:
        无返回值；断言失败时抛出异常。
    """
    adapter = RecordingAdapter()
    hub = GatewayCallbackHub([adapter])

    data = _run(hub.async_pre_call_hook(None, None, {"model": "x"}, "completion"))
    assert data["recorded"]

    kwargs = _run(hub.async_pre_call_deployment_hook({}, "anthropic_messages"))
    assert kwargs["deployment_recorded"] == "anthropic_messages"

    _run(hub.async_log_failure_event({}, RuntimeError("boom"), None, None))
    hub.log_pre_api_call("model", [], {})

    assert adapter.events == [
        "async_pre_call_hook",
        "async_pre_call_deployment_hook",
        "async_log_failure_event",
        "log_pre_api_call",
    ]
    print("gateway callback hub ok")


if __name__ == "__main__":
    main()
