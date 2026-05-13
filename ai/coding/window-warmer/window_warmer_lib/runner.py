"""Coding Plan window warmer 运行循环。"""

from __future__ import annotations

import random
import time
from datetime import datetime

from .constants import MAX_SLEEP_CHUNK_SECONDS
from .models import AppConfig, PlanConfig
from .scheduler import build_warm_event, build_warm_events, next_warm_event, select_next_event
from .target import ensure_target_ready, send_warm_completion


def warm_plan(config: AppConfig, plan: PlanConfig, dry_run: bool = False) -> bool:
    """执行单个 plan 的预热请求。

    Args:
        config: 应用配置。
        plan: plan 配置。
        dry_run: 为 True 时只打印，不发送请求。

    Returns:
        预热成功时返回 True，否则返回 False。
    """
    started_at = time.monotonic()
    log(f"[{plan.name}] warm started target={config.target.name} model={plan.model} schedule_mode={plan.schedule_mode}")

    if dry_run or config.scheduler.dry_run:
        log(
            f"[{plan.name}] dry-run warm target={config.target.name} model={plan.model} "
            f"duration_ms={elapsed_ms(started_at)}"
        )
        return True

    ready, message, api_key = ensure_target_ready(
        config.target,
        log_fn=lambda readiness_message: log(f"[{plan.name}] {readiness_message}"),
    )
    if not ready:
        log(f"[{plan.name}] skip warm: {message} duration_ms={elapsed_ms(started_at)}")
        return False
    log(f"[{plan.name}] readiness check passed: {message}")

    attempts = plan.retry_count + 1
    for attempt in range(1, attempts + 1):
        attempt_started_at = time.monotonic()
        log(
            f"[{plan.name}] sending warm request target={config.target.name} model={plan.model} "
            f"base_url={config.target.base_url} attempt={attempt}/{attempts} "
            f"timeout={config.target.request_timeout_seconds}s max_tokens={plan.max_tokens}"
        )
        try:
            send_warm_completion(config.target, plan, api_key)
            log(
                f"[{plan.name}] warm succeeded target={config.target.name} "
                f"model={plan.model} attempt={attempt}/{attempts} "
                f"duration_ms={elapsed_ms(attempt_started_at)} total_duration_ms={elapsed_ms(started_at)}"
            )
            return True
        except Exception as exc:
            log(
                f"[{plan.name}] warm failed attempt={attempt}/{attempts} "
                f"duration_ms={elapsed_ms(attempt_started_at)} error={exc}"
            )
            if attempt < attempts and plan.retry_delay_seconds > 0:
                log(f"[{plan.name}] retrying warm in {plan.retry_delay_seconds}s")
                time.sleep(plan.retry_delay_seconds)
    log(f"[{plan.name}] warm exhausted attempts={attempts} total_duration_ms={elapsed_ms(started_at)}")
    return False


def run_once(config: AppConfig, dry_run: bool = False) -> int:
    """立即执行所有启用 plan 的预热。

    Args:
        config: 应用配置。
        dry_run: 为 True 时只打印，不发送请求。

    Returns:
        全部成功返回 0，否则返回 1。
    """
    enabled_plans = [plan for plan in config.plans if plan.enabled]
    if not enabled_plans:
        log("没有启用的 plan。")
        return 1

    log(f"run once started enabled_plans={len(enabled_plans)}")
    success = True
    for plan in enabled_plans:
        success = warm_plan(config, plan, dry_run=dry_run) and success
    log(f"run once finished success={str(success).lower()}")
    return 0 if success else 1


def print_next_event(config: AppConfig, rng: random.Random) -> int:
    """打印下一次计划触发事件。

    Args:
        config: 应用配置。
        rng: 随机数生成器。

    Returns:
        成功打印返回 0，没有启用 plan 返回 1。
    """
    event = next_warm_event(config.plans, datetime.now(), rng)
    if event is None:
        log("没有启用的 plan。")
        return 1
    log(
        f"next warm plan={event.plan.name} base_at={event.base_at.isoformat()} "
        f"run_at={event.run_at.isoformat()} jitter={event.jitter_seconds}s"
    )
    return 0


def run_watch(config: AppConfig, rng: random.Random, dry_run: bool = False) -> int:
    """运行长期 watch 调度循环。

    Args:
        config: 应用配置。
        rng: 随机数生成器。
        dry_run: 为 True 时只打印，不发送请求。

    Returns:
        正常退出返回 0。
    """
    if not config.scheduler.enabled:
        log("scheduler.enabled=false，窗口预热未启用。")
        return 0

    log("Coding Plan window warmer started.")
    events = build_warm_events(config.plans, datetime.now(), rng)
    while True:
        event = select_next_event(events)
        if event is None:
            log(f"没有启用的 plan，{config.scheduler.poll_interval_seconds}s 后重试。")
            interruptible_sleep(config.scheduler.poll_interval_seconds)
            events = build_warm_events(config.plans, datetime.now(), rng)
            continue

        log(
            f"next warm plan={event.plan.name} base_at={event.base_at.isoformat()} "
            f"run_at={event.run_at.isoformat()} jitter={event.jitter_seconds}s"
        )
        sleep_until(event.run_at)
        log(
            f"warm due plan={event.plan.name} base_at={event.base_at.isoformat()} "
            f"run_at={event.run_at.isoformat()} now={datetime.now().isoformat(timespec='seconds')}"
        )
        warm_plan(config, event.plan, dry_run=dry_run)
        events[event.plan.name] = build_warm_event(event.plan, datetime.now(), rng)


def sleep_until(target: datetime) -> None:
    """等待到目标时间。

    Args:
        target: 目标本地时间。

    Returns:
        无返回值。
    """
    while True:
        remaining = (target - datetime.now()).total_seconds()
        if remaining <= 0:
            return
        interruptible_sleep(min(remaining, MAX_SLEEP_CHUNK_SECONDS))


def interruptible_sleep(seconds: float) -> None:
    """执行可被 Ctrl+C 中断的睡眠。

    Args:
        seconds: 睡眠秒数。

    Returns:
        无返回值。
    """
    time.sleep(max(0, seconds))


def elapsed_ms(started_at: float) -> int:
    """计算从起点到当前的毫秒耗时。

    Args:
        started_at: `time.monotonic()` 记录的起点。

    Returns:
        非负毫秒数。
    """
    return max(0, round((time.monotonic() - started_at) * 1000))


def log(message: str) -> None:
    """输出带本地时间戳的日志。

    Args:
        message: 日志消息。

    Returns:
        无返回值。
    """
    print(f"{datetime.now().isoformat(timespec='seconds')} {message}", flush=True)
