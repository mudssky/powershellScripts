"""DeepSeek thinking sanitizer 结构诊断日志。"""

import logging
import os
from typing import Any

LOGGER = logging.getLogger("DeepSeekThinkingSanitizer")
LOG_EVENT = "deepseek thinking sanitized"


def log_sanitized_context(
    kwargs: dict[str, Any],
    stage: str,
    diagnostics: dict[str, Any],
) -> None:
    """输出不包含正文内容的 sanitizer 结构诊断日志。

    Args:
        kwargs: LiteLLM hook 传入的模型调用上下文。
        stage: 当前 hook 阶段名称。
        diagnostics: 清理核心返回的安全诊断字段。

    Returns:
        无返回值。
    """
    if not _debug_enabled():
        return

    metadata = kwargs.get("litellm_metadata") or kwargs.get("metadata") or {}
    additional_args = kwargs.get("additional_args") or {}
    fallback_depth = kwargs.get("fallback_depth")
    LOGGER.warning(
        "%s | %s",
        LOG_EVENT,
        {
            "stage": stage,
            "model": kwargs.get("model"),
            "model_group": metadata.get("model_group"),
            "deployment": metadata.get("deployment"),
            "deployment_model_name": metadata.get("deployment_model_name"),
            "api_base": additional_args.get("api_base") or metadata.get("api_base"),
            "fallback_depth": fallback_depth,
            "is_router_fallback": isinstance(fallback_depth, int) and fallback_depth > 0,
            **diagnostics,
        },
    )


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
