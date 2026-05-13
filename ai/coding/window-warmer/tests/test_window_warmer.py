"""Coding Plan window warmer 单元测试。"""

from __future__ import annotations

import random
import sys
import unittest
from datetime import datetime, time
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import window_warmer_lib as warmer


class WindowWarmerScheduleTests(unittest.TestCase):
    """验证窗口预热调度计算。"""

    def test_fixed_times_uses_next_day_after_last_time(self) -> None:
        """固定时间模式在当天最后一个时间后应切到次日首个时间。

        Args:
            None.

        Returns:
            无返回值。
        """
        next_time = warmer.next_fixed_base_time(
            (time(8), time(13), time(18), time(23)),
            datetime(2026, 5, 13, 23, 30),
        )

        self.assertEqual(next_time, datetime(2026, 5, 14, 8, 0))

    def test_interval_mode_continues_across_midnight(self) -> None:
        """interval 模式应按连续窗口跨天推导。

        Args:
            None.

        Returns:
            无返回值。
        """
        plan = warmer.parse_plan_config(
            {
                "name": "glm",
                "model": "GLM-5.1",
                "schedule_mode": "interval",
                "start_time": "08:00",
                "window": "5h",
            },
            warmer.SchedulerConfig(True, 60, 0, 1, 30, False),
        )

        next_time = warmer.next_base_time(plan, datetime(2026, 5, 14, 4, 30))

        self.assertEqual(next_time, datetime(2026, 5, 14, 9, 0))

    def test_next_warm_event_selects_earliest_plan(self) -> None:
        """多 plan 调度应选择实际触发时间最早的事件。

        Args:
            None.

        Returns:
            无返回值。
        """
        scheduler = warmer.SchedulerConfig(True, 60, 0, 1, 30, False)
        later = warmer.parse_plan_config(
            {
                "name": "later",
                "model": "GLM-5.1",
                "schedule_mode": "fixed_times",
                "times": ["13:00"],
                "jitter_seconds": 0,
            },
            scheduler,
        )
        earlier = warmer.parse_plan_config(
            {
                "name": "earlier",
                "model": "GLM-5.1",
                "schedule_mode": "fixed_times",
                "times": ["08:00"],
                "jitter_seconds": 0,
            },
            scheduler,
        )

        event = warmer.next_warm_event((later, earlier), datetime(2026, 5, 13, 7, 0), random.Random(1))

        self.assertIsNotNone(event)
        self.assertEqual(event.plan.name, "earlier")
        self.assertEqual(event.run_at, datetime(2026, 5, 13, 8, 0))

    def test_parse_config_supports_multiple_plans(self) -> None:
        """TOML 配置模型应支持多个独立 plan。

        Args:
            None.

        Returns:
            无返回值。
        """
        config = warmer.parse_config(
            {
                "target": {"base_url": "https://open.bigmodel.cn/api/coding/paas/v4"},
                "scheduler": {"default_jitter_seconds": 0},
                "plans": [
                    {
                        "name": "glm",
                        "model": "GLM-5.1",
                        "schedule_mode": "fixed_times",
                        "times": ["08:00"],
                    },
                    {
                        "name": "other",
                        "model": "other-model",
                        "schedule_mode": "interval",
                        "start_at": "2026-05-13T08:00:00",
                        "window": "6h",
                    },
                ],
            },
            Path("/tmp"),
        )

        self.assertEqual([plan.name for plan in config.plans], ["glm", "other"])
        self.assertEqual(config.plans[1].window_seconds, 21600)

    def test_select_next_event_keeps_simultaneous_plan_events(self) -> None:
        """同一基准时间的多个 plan 应能留在事件队列中逐个执行。

        Args:
            None.

        Returns:
            无返回值。
        """
        scheduler = warmer.SchedulerConfig(True, 60, 0, 1, 30, False)
        plan_a = warmer.parse_plan_config(
            {
                "name": "a",
                "model": "GLM-5.1",
                "schedule_mode": "fixed_times",
                "times": ["08:00"],
                "jitter_seconds": 0,
            },
            scheduler,
        )
        plan_b = warmer.parse_plan_config(
            {
                "name": "b",
                "model": "GLM-5.1",
                "schedule_mode": "fixed_times",
                "times": ["08:00"],
                "jitter_seconds": 0,
            },
            scheduler,
        )
        now = datetime(2026, 5, 13, 7, 0)
        events = warmer.build_warm_events((plan_a, plan_b), now, random.Random(1))

        first = warmer.select_next_event(events)
        self.assertIsNotNone(first)
        events.pop(first.plan.name)
        second = warmer.select_next_event(events)

        self.assertIsNotNone(second)
        self.assertNotEqual(first.plan.name, second.plan.name)
        self.assertEqual(second.run_at, datetime(2026, 5, 13, 8, 0))


class WindowWarmerHttpTests(unittest.TestCase):
    """验证不会访问真实网络的请求构造逻辑。"""

    def test_send_warm_completion_uses_plan_and_direct_target(self) -> None:
        """预热请求应通过 LiteLLM SDK 直连配置目标。

        Args:
            None.

        Returns:
            无返回值。
        """
        plan = warmer.parse_plan_config(
            {
                "name": "glm",
                "model": "openai/GLM-5.1",
                "prompt": "hello",
                "schedule_mode": "fixed_times",
                "times": ["08:00"],
            },
            warmer.SchedulerConfig(True, 60, 120, 1, 30, False),
        )
        target = warmer.TargetConfig(
            name="z-ai",
            base_url="https://open.bigmodel.cn/api/coding/paas/v4",
            container_name=None,
            api_key_env="Z_AI_API_KEY",
            env_file=None,
            health_path="/models",
            request_timeout_seconds=30,
        )

        with patch("window_warmer_lib.target.call_litellm_completion") as completion:
            warmer.send_warm_completion(target, plan, "sk-test")

        completion.assert_called_once_with(
            model="openai/GLM-5.1",
            messages=[{"role": "user", "content": "hello"}],
            api_base="https://open.bigmodel.cn/api/coding/paas/v4",
            api_key="sk-test",
            timeout=30,
            max_tokens=16,
            temperature=0,
        )

    def test_dry_run_skips_readiness_checks(self) -> None:
        """dry-run 应完全跳过 Docker 与 API 检查。

        Args:
            None.

        Returns:
            无返回值。
        """
        plan = warmer.parse_plan_config(
            {
                "name": "glm",
                "model": "GLM-5.1",
                "schedule_mode": "fixed_times",
                "times": ["08:00"],
            },
            warmer.SchedulerConfig(True, 60, 120, 1, 30, False),
        )
        config = warmer.AppConfig(
            target=warmer.TargetConfig(
                name="test-target",
                base_url="http://127.0.0.1:34000",
                container_name="missing",
                api_key_env="MISSING_KEY",
                env_file=None,
                health_path="/health",
                request_timeout_seconds=1,
            ),
            scheduler=warmer.SchedulerConfig(True, 60, 120, 1, 30, False),
            plans=(plan,),
        )

        self.assertTrue(warmer.warm_plan(config, plan, dry_run=True))


if __name__ == "__main__":
    unittest.main()
