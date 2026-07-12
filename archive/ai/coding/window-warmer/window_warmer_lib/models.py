"""Coding Plan window warmer 配置模型。"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from datetime import time as time_of_day
from pathlib import Path


@dataclass(frozen=True)
class TargetConfig:
    """预热目标 HTTP 服务连接配置。

    Args:
        name: 目标服务诊断名称。
        base_url: 目标服务基础地址。
        container_name: 可选本机 Docker 容器名称；为空时不检查容器。
        api_key_env: 可选 API key 环境变量名；为空时不附加鉴权头。
        env_file: 可选 `.env.local` 文件路径。
        health_path: 可选健康检查路径；为空时不检查 API 健康端点。
        request_timeout_seconds: HTTP 请求超时时间。

    Returns:
        数据类实例，无额外返回。
    """

    name: str
    base_url: str
    container_name: str | None
    api_key_env: str | None
    env_file: Path | None
    health_path: str | None
    request_timeout_seconds: int


@dataclass(frozen=True)
class SchedulerConfig:
    """调度器全局配置。

    Args:
        enabled: 是否启用窗口预热。
        poll_interval_seconds: 没有可运行 plan 时的等待秒数。
        default_jitter_seconds: plan 未配置 jitter 时使用的默认随机偏移秒数。
        default_retry_count: plan 未配置 retry_count 时使用的默认重试次数。
        default_retry_delay_seconds: plan 未配置 retry_delay_seconds 时使用的默认重试间隔秒数。
        dry_run: 为 True 时只打印计划，不发送真实请求。

    Returns:
        数据类实例，无额外返回。
    """

    enabled: bool
    poll_interval_seconds: int
    default_jitter_seconds: int
    default_retry_count: int
    default_retry_delay_seconds: int
    dry_run: bool


@dataclass(frozen=True)
class PlanConfig:
    """单个 Coding Plan 预热配置。

    Args:
        name: plan 诊断名称。
        enabled: 是否启用该 plan。
        model: 目标服务接收的模型名。
        prompt: 预热使用的轻量 prompt。
        max_tokens: 预热响应最大 token 数。
        temperature: 预热请求 temperature 参数。
        schedule_mode: 调度模式，支持 `fixed_times` 和 `interval`。
        times: `fixed_times` 模式下的每日时间点。
        start_time: `interval` 模式下的本地锚点时间。
        start_at: `interval` 模式下的绝对本地锚点时间。
        window_seconds: `interval` 模式下的窗口秒数。
        jitter_seconds: 触发时间相对基准时间的随机后移秒数。
        retry_count: 单次预热失败后的额外重试次数。
        retry_delay_seconds: 单次预热失败后的重试等待秒数。

    Returns:
        数据类实例，无额外返回。
    """

    name: str
    enabled: bool
    model: str
    prompt: str
    max_tokens: int
    temperature: float
    schedule_mode: str
    times: tuple[time_of_day, ...]
    start_time: time_of_day | None
    start_at: datetime | None
    window_seconds: int | None
    jitter_seconds: int
    retry_count: int
    retry_delay_seconds: int


@dataclass(frozen=True)
class AppConfig:
    """窗口预热脚本完整配置。

    Args:
        target: 预热目标服务连接配置。
        scheduler: 调度器全局配置。
        plans: 多个 Coding Plan 预热配置。

    Returns:
        数据类实例，无额外返回。
    """

    target: TargetConfig
    scheduler: SchedulerConfig
    plans: tuple[PlanConfig, ...]


@dataclass(frozen=True)
class WarmEvent:
    """一次计划中的预热事件。

    Args:
        plan: 需要执行的 plan。
        base_at: 未叠加 jitter 的基准触发时间。
        run_at: 叠加 jitter 后的实际触发时间。
        jitter_seconds: 本次事件抽到的随机偏移秒数。

    Returns:
        数据类实例，无额外返回。
    """

    plan: PlanConfig
    base_at: datetime
    run_at: datetime
    jitter_seconds: int
