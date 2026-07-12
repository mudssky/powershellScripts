"""Coding Plan window warmer 配置解析。"""

from __future__ import annotations

from datetime import datetime
from datetime import time as time_of_day
from pathlib import Path
from typing import Any

import tomllib

from .constants import (
    DEFAULT_HEALTH_PATH,
    DEFAULT_JITTER_SECONDS,
    DEFAULT_POLL_SECONDS,
    DEFAULT_REQUEST_TIMEOUT_SECONDS,
    DEFAULT_RETRY_COUNT,
    DEFAULT_RETRY_DELAY_SECONDS,
    DEFAULT_TARGET_BASE_URL,
    DEFAULT_TARGET_NAME,
)
from .models import AppConfig, PlanConfig, SchedulerConfig, TargetConfig


def load_config(path: Path) -> AppConfig:
    """读取并解析脚本配置。

    Args:
        path: TOML 配置文件路径。

    Returns:
        应用配置对象。
    """
    with path.open("rb") as config_file:
        raw_config = tomllib.load(config_file)
    return parse_config(raw_config, path.parent)


def parse_config(raw_config: dict[str, Any], config_dir: Path) -> AppConfig:
    """把 TOML 字典解析为强类型配置。

    Args:
        raw_config: tomllib 解析出的配置字典。
        config_dir: 配置文件所在目录，用于解析相对路径。

    Returns:
        应用配置对象。
    """
    scheduler = parse_scheduler_config(raw_config.get("scheduler") or {})
    target = parse_target_config(raw_config.get("target") or {}, config_dir)
    raw_plans = raw_config.get("plans")
    if not isinstance(raw_plans, list) or not raw_plans:
        raise ValueError("配置必须包含至少一个 [[plans]]。")

    plans = tuple(parse_plan_config(plan, scheduler) for plan in raw_plans)
    validate_unique_plan_names(plans)
    return AppConfig(target=target, scheduler=scheduler, plans=plans)


def validate_unique_plan_names(plans: tuple[PlanConfig, ...]) -> None:
    """校验 plan 名称不能重复。

    Args:
        plans: 已解析的 plan 配置列表。

    Returns:
        无返回值；名称重复时抛出异常。
    """
    seen: set[str] = set()
    for plan in plans:
        if plan.name in seen:
            raise ValueError(f"plan 名称重复: {plan.name}")
        seen.add(plan.name)


def parse_target_config(raw_config: dict[str, Any], config_dir: Path) -> TargetConfig:
    """解析目标服务连接配置。

    Args:
        raw_config: `[target]` 配置字典。
        config_dir: 配置文件所在目录，用于解析相对 env 文件。

    Returns:
        目标服务连接配置。
    """
    if not isinstance(raw_config, dict):
        raise ValueError("[target] 必须是对象。")

    env_file_value = raw_config.get("env_file")
    env_file = None
    if env_file_value:
        env_file = resolve_config_path(config_dir, require_string(env_file_value, "target.env_file"))

    container_name = parse_optional_string(raw_config.get("container_name"), "target.container_name")
    api_key_env = parse_optional_string(raw_config.get("api_key_env"), "target.api_key_env")
    health_path_value = parse_optional_string(raw_config.get("health_path", DEFAULT_HEALTH_PATH), "target.health_path")

    return TargetConfig(
        name=str(raw_config.get("name", DEFAULT_TARGET_NAME)).strip() or DEFAULT_TARGET_NAME,
        base_url=require_string(raw_config.get("base_url", DEFAULT_TARGET_BASE_URL), "target.base_url").rstrip("/"),
        container_name=container_name,
        api_key_env=api_key_env,
        env_file=env_file,
        health_path=normalize_path(health_path_value) if health_path_value else None,
        request_timeout_seconds=require_positive_int(
            raw_config.get("request_timeout_seconds", DEFAULT_REQUEST_TIMEOUT_SECONDS),
            "target.request_timeout_seconds",
        ),
    )


def parse_scheduler_config(raw_config: dict[str, Any]) -> SchedulerConfig:
    """解析调度器全局配置。

    Args:
        raw_config: `[scheduler]` 配置字典。

    Returns:
        调度器配置。
    """
    return SchedulerConfig(
        enabled=bool(raw_config.get("enabled", True)),
        poll_interval_seconds=require_positive_int(
            raw_config.get("poll_interval_seconds", DEFAULT_POLL_SECONDS),
            "scheduler.poll_interval_seconds",
        ),
        default_jitter_seconds=require_non_negative_int(
            raw_config.get("default_jitter_seconds", DEFAULT_JITTER_SECONDS),
            "scheduler.default_jitter_seconds",
        ),
        default_retry_count=require_non_negative_int(
            raw_config.get("default_retry_count", DEFAULT_RETRY_COUNT),
            "scheduler.default_retry_count",
        ),
        default_retry_delay_seconds=require_non_negative_int(
            raw_config.get("default_retry_delay_seconds", DEFAULT_RETRY_DELAY_SECONDS),
            "scheduler.default_retry_delay_seconds",
        ),
        dry_run=bool(raw_config.get("dry_run", False)),
    )


def parse_plan_config(raw_config: Any, scheduler: SchedulerConfig) -> PlanConfig:
    """解析单个 `[[plans]]` 配置。

    Args:
        raw_config: 单个 plan 的 TOML 字典。
        scheduler: 调度器默认值配置。

    Returns:
        plan 配置对象。
    """
    if not isinstance(raw_config, dict):
        raise ValueError("[[plans]] 中的每个条目都必须是对象。")

    name = require_string(raw_config.get("name"), "plans.name")
    schedule_mode = require_string(raw_config.get("schedule_mode"), f"plans.{name}.schedule_mode")
    if schedule_mode not in {"fixed_times", "interval"}:
        raise ValueError(f"plans.{name}.schedule_mode 只能是 fixed_times 或 interval。")

    times: tuple[time_of_day, ...] = ()
    start_time: time_of_day | None = None
    start_at: datetime | None = None
    window_seconds: int | None = None

    if schedule_mode == "fixed_times":
        times = parse_time_list(raw_config.get("times"), f"plans.{name}.times")
    else:
        start_at = parse_optional_datetime(raw_config.get("start_at"), f"plans.{name}.start_at")
        start_time = parse_optional_time(raw_config.get("start_time"), f"plans.{name}.start_time")
        if start_at is None and start_time is None:
            raise ValueError(f"plans.{name} 使用 interval 模式时必须配置 start_at 或 start_time。")
        window_seconds = parse_duration_seconds(raw_config.get("window"), f"plans.{name}.window")

    return PlanConfig(
        name=name,
        enabled=bool(raw_config.get("enabled", True)),
        model=require_string(raw_config.get("model"), f"plans.{name}.model"),
        prompt=str(raw_config.get("prompt", "你好吗")),
        max_tokens=require_positive_int(raw_config.get("max_tokens", 16), f"plans.{name}.max_tokens"),
        temperature=float(raw_config.get("temperature", 0)),
        schedule_mode=schedule_mode,
        times=times,
        start_time=start_time,
        start_at=start_at,
        window_seconds=window_seconds,
        jitter_seconds=require_non_negative_int(
            raw_config.get("jitter_seconds", scheduler.default_jitter_seconds),
            f"plans.{name}.jitter_seconds",
        ),
        retry_count=require_non_negative_int(
            raw_config.get("retry_count", scheduler.default_retry_count),
            f"plans.{name}.retry_count",
        ),
        retry_delay_seconds=require_non_negative_int(
            raw_config.get("retry_delay_seconds", scheduler.default_retry_delay_seconds),
            f"plans.{name}.retry_delay_seconds",
        ),
    )


def resolve_config_path(config_dir: Path, path_value: str) -> Path:
    """解析配置中的路径值。

    Args:
        config_dir: 配置文件所在目录。
        path_value: 配置中写入的路径。

    Returns:
        绝对或相对配置目录解析后的路径。
    """
    path = Path(path_value)
    if path.is_absolute():
        return path
    return config_dir / path


def require_string(value: Any, field_name: str) -> str:
    """读取必填字符串字段。

    Args:
        value: 待校验的值。
        field_name: 用于错误信息的字段名。

    Returns:
        去除首尾空白后的字符串。
    """
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} 必须是非空字符串。")
    return value.strip()


def parse_optional_string(value: Any, field_name: str) -> str | None:
    """读取可选字符串字段。

    Args:
        value: 待校验的值。
        field_name: 用于错误信息的字段名。

    Returns:
        去除首尾空白后的字符串；为空时返回 None。
    """
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{field_name} 必须是字符串。")
    text = value.strip()
    return text or None


def require_positive_int(value: Any, field_name: str) -> int:
    """读取正整数字段。

    Args:
        value: 待校验的值。
        field_name: 用于错误信息的字段名。

    Returns:
        正整数值。
    """
    integer = require_int(value, field_name)
    if integer <= 0:
        raise ValueError(f"{field_name} 必须大于 0。")
    return integer


def require_non_negative_int(value: Any, field_name: str) -> int:
    """读取非负整数字段。

    Args:
        value: 待校验的值。
        field_name: 用于错误信息的字段名。

    Returns:
        非负整数值。
    """
    integer = require_int(value, field_name)
    if integer < 0:
        raise ValueError(f"{field_name} 不能小于 0。")
    return integer


def require_int(value: Any, field_name: str) -> int:
    """读取整数字段。

    Args:
        value: 待校验的值。
        field_name: 用于错误信息的字段名。

    Returns:
        整数值。
    """
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{field_name} 必须是整数。")
    return value


def normalize_path(path_value: str) -> str:
    """规范化 HTTP API 路径。

    Args:
        path_value: 用户配置的路径。

    Returns:
        以 `/` 开头的路径。
    """
    if not path_value:
        raise ValueError("HTTP API path 不能为空。")
    return path_value if path_value.startswith("/") else f"/{path_value}"


def parse_time_list(value: Any, field_name: str) -> tuple[time_of_day, ...]:
    """解析每日固定时间列表。

    Args:
        value: TOML 中的时间字符串列表。
        field_name: 用于错误信息的字段名。

    Returns:
        排序后的 time 元组。
    """
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field_name} 必须是非空字符串数组。")
    return tuple(sorted(parse_time_of_day(item, f"{field_name}[]") for item in value))


def parse_optional_time(value: Any, field_name: str) -> time_of_day | None:
    """解析可选本地时间。

    Args:
        value: 时间字符串或空值。
        field_name: 用于错误信息的字段名。

    Returns:
        解析成功的 time；空值返回 None。
    """
    if value is None:
        return None
    return parse_time_of_day(value, field_name)


def parse_time_of_day(value: Any, field_name: str) -> time_of_day:
    """解析 `HH:MM` 或 `HH:MM:SS` 时间。

    Args:
        value: 时间字符串。
        field_name: 用于错误信息的字段名。

    Returns:
        本地 time 值。
    """
    text = require_string(value, field_name)
    parts = text.split(":")
    if len(parts) not in {2, 3}:
        raise ValueError(f"{field_name} 必须使用 HH:MM 或 HH:MM:SS 格式。")
    try:
        hour = int(parts[0])
        minute = int(parts[1])
        second = int(parts[2]) if len(parts) == 3 else 0
        return time_of_day(hour=hour, minute=minute, second=second)
    except ValueError as exc:
        raise ValueError(f"{field_name} 不是有效时间。") from exc


def parse_optional_datetime(value: Any, field_name: str) -> datetime | None:
    """解析可选本地日期时间。

    Args:
        value: ISO 日期时间字符串或空值。
        field_name: 用于错误信息的字段名。

    Returns:
        解析后的 datetime；空值返回 None。
    """
    if value is None:
        return None
    text = require_string(value, field_name)
    try:
        return datetime.fromisoformat(text)
    except ValueError as exc:
        raise ValueError(f"{field_name} 必须是 ISO 日期时间，例如 2026-05-13T08:00:00。") from exc


def parse_duration_seconds(value: Any, field_name: str) -> int:
    """解析持续时间字符串。

    Args:
        value: 持续时间字符串，支持 `s`、`m`、`h` 后缀。
        field_name: 用于错误信息的字段名。

    Returns:
        持续时间秒数。
    """
    text = require_string(value, field_name).lower()
    unit = text[-1]
    number_text = text[:-1]
    multiplier = {"s": 1, "m": 60, "h": 3600}.get(unit)
    if multiplier is None:
        raise ValueError(f"{field_name} 必须使用 s、m 或 h 后缀。")
    try:
        number = float(number_text)
    except ValueError as exc:
        raise ValueError(f"{field_name} 的数值部分无效。") from exc
    seconds = int(number * multiplier)
    if seconds <= 0:
        raise ValueError(f"{field_name} 必须大于 0。")
    return seconds
