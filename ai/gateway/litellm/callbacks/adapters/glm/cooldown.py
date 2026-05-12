"""GLM 429 reset 时间感知 cooldown adapter。"""

import json
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from callbacks.framework.adapters import AdapterResult, CooldownAdapter

LOGGER = logging.getLogger("GlmCooldownAdapter")
GLM_RESET_PATTERN = re.compile(r"限额将在\s*(?P<reset_at>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*重置")
GLM_QUOTA_MARKERS = ("使用上限", "限额", "quota", "rate limit", "429")
DEFAULT_MODEL_FALLBACKS = {
    "cc-glmplan-opus": "claude-code-deepseek-v4-pro",
    "cc-glmplan-haiku": "claude-code-deepseek-v4-flash",
}


@dataclass(frozen=True)
class GlmCooldownConfig:
    """GLM cooldown adapter 配置。

    Args:
        enabled: 是否启用 adapter。
        reset_buffer_seconds: GLM reset 时间后额外延迟的秒数。
        fallback_cooldown_seconds: 无法解析 reset 时间时使用的保守冷却秒数。
        model_fallbacks: GLM model group 到 DeepSeek fallback model group 的映射。

    Returns:
        数据类实例，无额外返回。
    """

    enabled: bool = True
    reset_buffer_seconds: int = 60
    fallback_cooldown_seconds: int = 18_000
    model_fallbacks: dict[str, str] | None = None


class GlmCooldownAdapter(CooldownAdapter):
    """根据 GLM 429 reset 时间在请求前避让 GLM 主路由。"""

    name = "glm_cooldown"

    def __init__(self, config: GlmCooldownConfig | None = None) -> None:
        """初始化 GLM cooldown adapter。

        Args:
            config: adapter 配置；为空时使用环境变量和默认值。

        Returns:
            无返回值。
        """
        resolved_config = config or _config_from_environment()
        super().__init__(enabled=resolved_config.enabled, fail_open=True)
        self.config = resolved_config
        self._cooldown_until: dict[str, datetime] = {}

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict[str, Any],
        call_type: Any,
    ) -> dict[str, Any]:
        """在 Router 选 deployment 前把冷却中的 GLM 入口切到 DeepSeek。

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

        fallback_model = self._fallback_for_model(model)
        if fallback_model is None or not self.is_model_in_cooldown(model):
            return data

        data["model"] = fallback_model
        self._log(
            "glm cooldown route switched",
            {
                "stage": "async_pre_call_hook",
                "model": model,
                "fallback_model": fallback_model,
                "cooldown_until": self._cooldown_until[model].isoformat(),
            },
        )
        return data

    async def async_log_failure_event(
        self,
        kwargs: dict[str, Any],
        response_obj: Any,
        start_time: Any,
        end_time: Any,
    ) -> AdapterResult:
        """在失败日志阶段记录 GLM 429 reset 时间。

        Args:
            kwargs: LiteLLM 失败事件上下文。
            response_obj: LiteLLM 传入的异常或失败响应对象。
            start_time: 调用开始时间。
            end_time: 调用结束时间。

        Returns:
            adapter 执行结果，解析到 cooldown 时 changed 为 True。
        """
        model = _model_from_failure_context(kwargs)
        if model not in self.model_fallbacks:
            return AdapterResult(self.name, "async_log_failure_event")

        if not is_glm_quota_error(response_obj):
            return AdapterResult(self.name, "async_log_failure_event")

        reset_at = parse_glm_reset_time(response_obj)
        cooldown_until = self._cooldown_until_from_reset(reset_at)
        if cooldown_until is None:
            return AdapterResult(self.name, "async_log_failure_event")

        self._cooldown_until[model] = cooldown_until
        diagnostics = {
            "stage": "async_log_failure_event",
            "model": model,
            "cooldown_until": cooldown_until.isoformat(),
            "reset_detected": reset_at is not None,
        }
        self._log("glm cooldown updated", diagnostics)
        return AdapterResult(
            self.name,
            "async_log_failure_event",
            changed=True,
            diagnostics=diagnostics,
        )

    @property
    def model_fallbacks(self) -> dict[str, str]:
        """读取 GLM 模型到 fallback 模型的映射。

        Args:
            None.

        Returns:
            模型 fallback 映射字典。
        """
        return self.config.model_fallbacks or DEFAULT_MODEL_FALLBACKS

    def is_model_in_cooldown(
        self,
        model: str,
        now: datetime | None = None,
    ) -> bool:
        """判断指定模型是否仍处于 cooldown。

        Args:
            model: LiteLLM model group 名称。
            now: 当前时间；测试可传入固定时间。

        Returns:
            模型仍在 cooldown 窗口内时返回 True，否则返回 False。
        """
        cooldown_until = self._cooldown_until.get(model)
        if cooldown_until is None:
            return False

        current_time = now or datetime.now()
        if current_time < cooldown_until:
            return True

        self._cooldown_until.pop(model, None)
        return False

    def _fallback_for_model(self, model: str) -> str | None:
        """读取模型对应的 fallback 模型。

        Args:
            model: LiteLLM model group 名称。

        Returns:
            命中配置时返回 fallback model group，否则返回 None。
        """
        return self.model_fallbacks.get(model)

    def _cooldown_until_from_reset(
        self,
        reset_at: datetime | None,
        now: datetime | None = None,
    ) -> datetime | None:
        """根据 reset 时间计算最终 cooldown 截止时间。

        Args:
            reset_at: GLM 错误体中的 reset 时间；为空时使用固定兜底冷却。
            now: 当前时间；测试可传入固定时间。

        Returns:
            cooldown 截止时间；无法确定时返回 None。
        """
        current_time = now or datetime.now()
        if reset_at is not None:
            cooldown_until = reset_at + timedelta(seconds=self.config.reset_buffer_seconds)
            return max(cooldown_until, current_time + timedelta(seconds=1))

        return current_time + timedelta(seconds=self.config.fallback_cooldown_seconds)

    def _log(self, event: str, diagnostics: dict[str, Any]) -> None:
        """输出不包含正文内容的 cooldown 诊断日志。

        Args:
            event: 日志事件名。
            diagnostics: 安全诊断字段。

        Returns:
            无返回值。
        """
        LOGGER.warning("%s | %s", event, diagnostics)


def parse_glm_reset_time(error: Any) -> datetime | None:
    """从 GLM 429 错误结构中解析额度 reset 时间。

    Args:
        error: LiteLLM 失败响应、异常对象、JSON 字符串或字典。

    Returns:
        解析成功时返回无时区 datetime，否则返回 None。
    """
    message = _error_message(error)
    if message is None:
        return None

    match = GLM_RESET_PATTERN.search(message)
    if match is None:
        return None

    try:
        return datetime.strptime(match.group("reset_at"), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def is_glm_quota_error(error: Any) -> bool:
    """判断失败对象是否像 GLM 额度/限流错误。

    Args:
        error: LiteLLM 失败响应、异常对象、JSON 字符串或字典。

    Returns:
        命中 GLM 额度或限流错误特征时返回 True，否则返回 False。
    """
    if parse_glm_reset_time(error) is not None:
        return True

    message = _error_message(error)
    if message is None:
        return False

    normalized = message.lower()
    return any(marker in normalized for marker in GLM_QUOTA_MARKERS)


def _error_message(error: Any) -> str | None:
    """从异常或响应对象中提取错误 message 文本。

    Args:
        error: 任意失败对象。

    Returns:
        找到 message 时返回字符串，否则返回 None。
    """
    for candidate in _error_candidates(error):
        message = _message_from_candidate(candidate)
        if message:
            return message
    return None


def _error_candidates(error: Any) -> list[Any]:
    """枚举可能包含 GLM 错误正文的对象。

    Args:
        error: 任意失败对象。

    Returns:
        候选对象列表。
    """
    candidates = [error]
    for attr in ("message", "detail", "response", "body", "text"):
        value = getattr(error, attr, None)
        if value is not None:
            candidates.append(value)
    if not isinstance(error, str):
        candidates.append(str(error))
    return candidates


def _message_from_candidate(candidate: Any) -> str | None:
    """从单个候选对象中提取 message 字段。

    Args:
        candidate: 字典、JSON 字符串或普通对象。

    Returns:
        提取成功时返回 message 文本，否则返回 None。
    """
    if isinstance(candidate, dict):
        error = candidate.get("error")
        if isinstance(error, dict) and isinstance(error.get("message"), str):
            return error["message"]
        if isinstance(candidate.get("message"), str):
            return candidate["message"]

    if isinstance(candidate, str):
        parsed = _parse_json(candidate)
        if parsed is not None:
            return _message_from_candidate(parsed)
        return candidate

    return None


def _parse_json(value: str) -> Any | None:
    """安全解析 JSON 字符串。

    Args:
        value: 待解析的字符串。

    Returns:
        解析成功时返回 JSON 值，否则返回 None。
    """
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def _model_from_failure_context(kwargs: dict[str, Any]) -> str | None:
    """从 LiteLLM 失败上下文中读取原始 model group。

    Args:
        kwargs: LiteLLM 失败事件上下文。

    Returns:
        找到模型名时返回字符串，否则返回 None。
    """
    metadata = kwargs.get("litellm_metadata") or kwargs.get("metadata") or {}
    for candidate in (
        metadata.get("model_group"),
        kwargs.get("model"),
        metadata.get("deployment_model_name"),
    ):
        if isinstance(candidate, str):
            return candidate
    return None


def _config_from_environment() -> GlmCooldownConfig:
    """从环境变量读取 GLM cooldown adapter 配置。

    Args:
        None.

    Returns:
        GLM cooldown 配置对象。
    """
    return GlmCooldownConfig(
        enabled=_env_bool("LITELLM_GLM_COOLDOWN_ENABLED", True),
        reset_buffer_seconds=_env_int("LITELLM_GLM_RESET_BUFFER_SECONDS", 60),
        fallback_cooldown_seconds=_env_int(
            "LITELLM_GLM_FALLBACK_COOLDOWN_SECONDS",
            18_000,
        ),
    )


def _env_bool(name: str, default: bool) -> bool:
    """读取布尔环境变量。

    Args:
        name: 环境变量名称。
        default: 未设置时的默认值。

    Returns:
        解析后的布尔值。
    """
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() not in {"0", "false", "off", "no"}


def _env_int(name: str, default: int) -> int:
    """读取整数环境变量。

    Args:
        name: 环境变量名称。
        default: 未设置或格式无效时的默认值。

    Returns:
        解析后的整数值。
    """
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default
