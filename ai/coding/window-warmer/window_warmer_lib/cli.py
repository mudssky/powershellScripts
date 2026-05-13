"""Coding Plan window warmer 命令行入口。"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

import tomllib

from .config import load_config
from .constants import DEFAULT_CONFIG_NAME
from .runner import log, print_next_event, run_once, run_watch


def default_config_path() -> Path:
    """读取默认 TOML 配置路径。

    Args:
        None.

    Returns:
        默认配置文件路径。
    """
    return Path(__file__).resolve().parents[1] / DEFAULT_CONFIG_NAME


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """解析命令行参数。

    Args:
        argv: 可选参数列表；为空时读取当前进程参数。

    Returns:
        argparse 解析结果。
    """
    parser = argparse.ArgumentParser(description="Warm Coding Plan quota windows.")
    parser.add_argument(
        "--config",
        default=str(default_config_path()),
        help="TOML config path. Defaults to ai/coding/window-warmer/window-warmer.toml.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print scheduled events without sending warmup requests.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Send one warmup request for every enabled plan immediately, then exit.",
    )
    parser.add_argument(
        "--print-next",
        action="store_true",
        help="Print the next scheduled event and exit.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """脚本入口。

    Args:
        argv: 可选命令行参数。

    Returns:
        进程退出码。
    """
    args = parse_args(argv)
    config_path = Path(args.config)
    try:
        config = load_config(config_path)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
        print(f"加载配置失败: {exc}", file=sys.stderr)
        return 2

    rng = random.Random()
    dry_run = bool(args.dry_run)
    try:
        if args.print_next:
            return print_next_event(config, rng)
        if args.once:
            return run_once(config, dry_run=dry_run)
        return run_watch(config, rng, dry_run=dry_run)
    except KeyboardInterrupt:
        log("Coding Plan window warmer stopped.")
        return 0
