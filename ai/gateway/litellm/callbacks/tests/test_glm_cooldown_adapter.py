"""GLM cooldown adapter 回归测试。"""

import asyncio
import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from callbacks.adapters.glm.cooldown import (
    GlmCooldownAdapter,
    GlmCooldownConfig,
    is_glm_quota_error,
    parse_glm_reset_time,
)


def _run(coro: Any) -> Any:
    """执行异步测试协程。

    Args:
        coro: 待执行的协程对象。

    Returns:
        协程返回值。
    """
    return asyncio.run(coro)


def _sample_error() -> str:
    """构造 GLM 429 示例错误。

    Args:
        None.

    Returns:
        JSON 字符串形式的 GLM 错误。
    """
    return (
        '{"error":{"code":"1308","message":"已达到 5 小时的使用上限。'
        '您的限额将在 2026-05-08 05:32:56 重置。"},'
        '"request_id":"2026050801445754b5000d90034183"}'
    )


def main() -> None:
    """执行 GLM cooldown adapter 回归断言。

    Args:
        None.

    Returns:
        无返回值；断言失败时抛出异常。
    """
    logging.disable(logging.CRITICAL)

    reset_at = parse_glm_reset_time(_sample_error())
    assert reset_at == datetime(2026, 5, 8, 5, 32, 56)
    assert is_glm_quota_error(_sample_error())
    assert not is_glm_quota_error("upstream internal server error")

    config = GlmCooldownConfig(
        reset_buffer_seconds=60,
        fallback_cooldown_seconds=18_000,
    )
    adapter = GlmCooldownAdapter(config)
    cooldown_until = adapter._cooldown_until_from_reset(
        reset_at,
        now=datetime(2026, 5, 8, 1, 44, 57),
    )
    assert cooldown_until == datetime(2026, 5, 8, 5, 33, 56)

    fallback_until = adapter._cooldown_until_from_reset(
        None,
        now=datetime(2026, 5, 8, 1, 44, 57),
    )
    assert fallback_until == datetime(2026, 5, 8, 6, 44, 57)

    adapter._cooldown_until["cc-glmplan-opus"] = datetime.now() + timedelta(hours=1)
    data = {"model": "cc-glmplan-opus", "messages": []}
    routed = _run(adapter.async_pre_call_hook(None, None, data, "anthropic_messages"))
    assert routed is data
    assert routed["model"] == "claude-code-deepseek-v4-pro"

    kwargs = {
        "litellm_metadata": {
            "model_group": "cc-glmplan-haiku",
        }
    }
    result = _run(
        adapter.async_log_failure_event(
            kwargs,
            _sample_error(),
            None,
            None,
        )
    )
    assert result.changed
    assert adapter.is_model_in_cooldown("cc-glmplan-haiku")

    adapter._cooldown_until.pop("cc-glmplan-haiku", None)
    result = _run(
        adapter.async_log_failure_event(
            kwargs,
            "upstream internal server error",
            None,
            None,
        )
    )
    assert not result.changed
    assert not adapter.is_model_in_cooldown("cc-glmplan-haiku")

    print("glm cooldown adapter ok")


if __name__ == "__main__":
    main()
