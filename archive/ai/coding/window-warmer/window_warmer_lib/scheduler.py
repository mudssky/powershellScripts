"""Coding Plan window warmer 调度计算。"""

from __future__ import annotations

import random
from datetime import datetime, timedelta
from datetime import time as time_of_day

from .models import PlanConfig, WarmEvent


def next_base_time(plan: PlanConfig, now: datetime) -> datetime:
    """计算 plan 的下一次基准触发时间。

    Args:
        plan: plan 配置。
        now: 当前本地时间。

    Returns:
        下一次未叠加 jitter 的基准触发时间。
    """
    if plan.schedule_mode == "fixed_times":
        return next_fixed_base_time(plan.times, now)
    return next_interval_base_time(plan, now)


def next_fixed_base_time(times: tuple[time_of_day, ...], now: datetime) -> datetime:
    """计算固定每日时间列表的下一次触发时间。

    Args:
        times: 每日固定时间点。
        now: 当前本地时间。

    Returns:
        下一次固定时间触发点。
    """
    for day_offset in range(2):
        target_date = now.date() + timedelta(days=day_offset)
        for item in times:
            candidate = datetime.combine(target_date, item)
            if candidate > now:
                return candidate
    return datetime.combine(now.date() + timedelta(days=1), times[0])


def next_interval_base_time(plan: PlanConfig, now: datetime) -> datetime:
    """计算固定窗口长度模式的下一次触发时间。

    Args:
        plan: interval 模式 plan。
        now: 当前本地时间。

    Returns:
        下一次 interval 触发点。
    """
    if plan.window_seconds is None:
        raise ValueError(f"plans.{plan.name}.window 缺失。")

    anchor = interval_anchor(plan, now)
    elapsed_seconds = (now - anchor).total_seconds()
    if elapsed_seconds < 0:
        return anchor

    # 这里按连续时间轴推导窗口，而不是每天重置；适合“从首个请求开始计 N 小时”的套餐。
    steps = int(elapsed_seconds // plan.window_seconds) + 1
    return anchor + timedelta(seconds=steps * plan.window_seconds)


def interval_anchor(plan: PlanConfig, now: datetime) -> datetime:
    """计算 interval 模式的锚点时间。

    Args:
        plan: interval 模式 plan。
        now: 当前本地时间。

    Returns:
        用于连续窗口计算的锚点 datetime。
    """
    if plan.start_at is not None:
        return plan.start_at
    if plan.start_time is None:
        raise ValueError(f"plans.{plan.name}.start_time 缺失。")

    today_anchor = datetime.combine(now.date(), plan.start_time)
    if today_anchor <= now:
        return today_anchor
    return datetime.combine(now.date() - timedelta(days=1), plan.start_time)


def build_warm_event(plan: PlanConfig, now: datetime, rng: random.Random) -> WarmEvent:
    """构造 plan 的下一次预热事件。

    Args:
        plan: plan 配置。
        now: 当前本地时间。
        rng: 随机数生成器。

    Returns:
        预热事件。
    """
    base_at = next_base_time(plan, now)
    jitter = rng.randint(0, plan.jitter_seconds) if plan.jitter_seconds > 0 else 0
    return WarmEvent(
        plan=plan,
        base_at=base_at,
        run_at=base_at + timedelta(seconds=jitter),
        jitter_seconds=jitter,
    )


def next_warm_event(plans: tuple[PlanConfig, ...], now: datetime, rng: random.Random) -> WarmEvent | None:
    """从多个 plan 中选择最近的下一次预热事件。

    Args:
        plans: plan 配置列表。
        now: 当前本地时间。
        rng: 随机数生成器。

    Returns:
        最近的预热事件；没有启用 plan 时返回 None。
    """
    events = [build_warm_event(plan, now, rng) for plan in plans if plan.enabled]
    if not events:
        return None
    return min(events, key=lambda event: event.run_at)


def build_warm_events(plans: tuple[PlanConfig, ...], now: datetime, rng: random.Random) -> dict[str, WarmEvent]:
    """为每个启用 plan 建立下一次预热事件。

    Args:
        plans: plan 配置列表。
        now: 当前本地时间。
        rng: 随机数生成器。

    Returns:
        按 plan 名称索引的预热事件字典。
    """
    return {plan.name: build_warm_event(plan, now, rng) for plan in plans if plan.enabled}


def select_next_event(events: dict[str, WarmEvent]) -> WarmEvent | None:
    """从事件队列中选择最近的预热事件。

    Args:
        events: 按 plan 名称索引的预热事件字典。

    Returns:
        最近的预热事件；队列为空时返回 None。
    """
    if not events:
        return None
    return min(events.values(), key=lambda event: event.run_at)
