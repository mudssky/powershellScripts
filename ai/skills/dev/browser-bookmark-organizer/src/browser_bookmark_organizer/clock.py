"""统一时间封装。"""

from __future__ import annotations

from datetime import datetime


def now_local() -> datetime:
    """返回系统本地时区的当前时间。

    Args:
        None.

    Returns:
        datetime: 带系统本地时区信息的当前时间。
    """

    return datetime.now().astimezone()


def now_local_iso() -> str:
    """返回系统本地时区当前时间的 ISO 字符串。

    Args:
        None.

    Returns:
        str: ISO 8601 时间字符串。
    """

    return now_local().isoformat()


def filesystem_timestamp() -> str:
    """生成适合文件名的本地时间戳。

    Args:
        None.

    Returns:
        str: `YYYYMMDD-HHMMSS` 格式时间戳。
    """

    return now_local().strftime("%Y%m%d-%H%M%S")
