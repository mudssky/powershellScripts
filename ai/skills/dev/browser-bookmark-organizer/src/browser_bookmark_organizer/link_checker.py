"""HTTPX 链接检测逻辑。"""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import ssl
import time
from dataclasses import dataclass
from typing import Any, Callable
from urllib.parse import urlsplit

import httpx

from browser_bookmark_organizer.models import Bookmark

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class LinkCheckOptions:
    """链接检测选项。

    Args:
        timeout: 单个请求超时秒数。
        follow_redirects: 是否跟随 HTTP 重定向。
        concurrency: 最大并发请求数。
        delay: 请求启动间隔秒数。
        max_links: 最多检测的 HTTP/HTTPS 链接数；None 表示不限制。
        check_private_links: 是否检测局域网、Tailscale 和公司内网候选链接。
        network_context: 本次检测所处网络环境标签，用于报告复盘。

    Returns:
        LinkCheckOptions: 链接检测配置。
    """

    timeout: float = 10.0
    follow_redirects: bool = True
    concurrency: int = 32
    delay: float = 0.2
    max_links: int | None = None
    check_private_links: bool = False
    network_context: str = "default"


@dataclass(frozen=True, slots=True)
class LinkCheckResult:
    """单条链接检测结果。

    Args:
        order: 书签原始顺序。
        title: 书签标题。
        url: 原始 URL。
        folder_path: 书签所在文件夹路径。
        checked: 是否实际发起 HTTP 请求。
        skipped_reason: 未检测原因。
        network_context: 链接网络上下文分类。
        network_hint: 面向用户的网络环境提示。
        status_code: HTTP 状态码。
        final_url: 跟随重定向后的最终 URL。
        error_category: 错误类别。
        error_message: 简短错误信息。
        elapsed_ms: 请求耗时毫秒。

    Returns:
        LinkCheckResult: 可序列化的链接检测结果。
    """

    order: int
    title: str
    url: str
    folder_path: tuple[str, ...]
    checked: bool
    skipped_reason: str | None = None
    network_context: str = "public_web"
    network_hint: str | None = None
    status_code: int | None = None
    final_url: str | None = None
    error_category: str | None = None
    error_message: str | None = None
    elapsed_ms: int | None = None

    @property
    def is_problem(self) -> bool:
        """判断该结果是否需要人工关注。

        Args:
            self: 当前检测结果。

        Returns:
            bool: 错误或 4xx/5xx 状态返回 True。
        """

        return bool(
            self.error_category or (self.status_code is not None and self.status_code >= 400)
        )


async def check_links(
    bookmarks: tuple[Bookmark, ...] | list[Bookmark],
    options: LinkCheckOptions,
    transport: httpx.AsyncBaseTransport | None = None,
    on_progress: Callable[[int, int, list[LinkCheckResult]], None] | None = None,
) -> list[LinkCheckResult]:
    """并发检测书签链接状态。

    Args:
        bookmarks: 待检测书签。
        options: 链接检测选项。
        transport: 测试注入的 HTTPX transport；生产运行保持 None。
        on_progress: 每完成一个检测后的进度回调 (done, total, results)。

    Returns:
        list[LinkCheckResult]: 按原始书签顺序排列的检测结果。
    """

    selected = select_bookmarks_for_check(bookmarks, options.max_links, options.check_private_links)
    semaphore = asyncio.Semaphore(max(1, options.concurrency))
    rate_limiter = RequestRateLimiter(delay=max(0.0, options.delay))
    headers = {"User-Agent": "browser-bookmark-organizer/0.1"}
    timeout = httpx.Timeout(options.timeout)

    total = len(selected)
    completed: list[LinkCheckResult] = []
    lock = asyncio.Lock()

    async def _check_and_track(bookmark: Bookmark) -> LinkCheckResult:
        """检测单个链接并追踪进度。

        Args:
            bookmark: 待检测书签。

        Returns:
            LinkCheckResult: 检测结果。
        """
        result = await _check_one(bookmark, options, client, semaphore, rate_limiter)
        async with lock:
            completed.append(result)
            if on_progress:
                on_progress(len(completed), total, completed)
        return result

    async with httpx.AsyncClient(
        timeout=timeout,
        follow_redirects=options.follow_redirects,
        headers=headers,
        transport=transport,
    ) as client:
        tasks = [_check_and_track(bookmark) for bookmark in selected]
        await asyncio.gather(*tasks)
    return sorted(completed, key=lambda item: item.order)


def select_bookmarks_for_check(
    bookmarks: tuple[Bookmark, ...] | list[Bookmark],
    max_links: int | None,
    check_private_links: bool = False,
) -> list[Bookmark]:
    """选择需要输出检测结果的书签。

    Args:
        bookmarks: 原始书签列表。
        max_links: 最多实际检测的 HTTP/HTTPS 数量；None 表示不限制。
        check_private_links: 是否把私网类 HTTP/HTTPS 链接计入可检测数量。

    Returns:
        list[Bookmark]: 保留全部非 HTTP 跳过项，并限制 HTTP/HTTPS 检测项数量后的书签。
    """

    selected: list[Bookmark] = []
    checked_http_count = 0
    for bookmark in bookmarks:
        classification = classify_url_network(bookmark.url)
        if classification.is_checkable(check_private_links):
            if max_links is not None and checked_http_count >= max_links:
                continue
            checked_http_count += 1
        selected.append(bookmark)
    return selected


def is_http_url(url: str) -> bool:
    """判断 URL 是否可用 HTTPX 检测。

    Args:
        url: 原始 URL。

    Returns:
        bool: HTTP 或 HTTPS URL 返回 True。
    """

    return urlsplit(url).scheme.lower() in {"http", "https"}


@dataclass(frozen=True, slots=True)
class NetworkClassification:
    """URL 网络上下文分类。

    Args:
        context: 网络上下文，如 public_web、private_lan、tailscale。
        hint: 面向用户的检测环境提示。
        is_http: 是否是 HTTP/HTTPS URL。
        requires_context: 是否需要特定网络环境才能可靠检测。

    Returns:
        NetworkClassification: URL 网络上下文判断结果。
    """

    context: str
    hint: str | None
    is_http: bool
    requires_context: bool

    def is_checkable(self, check_private_links: bool) -> bool:
        """判断该链接在当前选项下是否会实际检测。

        Args:
            check_private_links: 是否允许检测私网类链接。

        Returns:
            bool: 会发起 HTTP 请求时返回 True。
        """

        return self.is_http and (check_private_links or not self.requires_context)


TAILSCALE_CGNAT = ipaddress.ip_network("100.64.0.0/10")
CORP_HINT_SUFFIXES = (
    ".internal",
    ".intranet",
    ".corp",
    ".lan",
    ".home",
)


def classify_url_network(url: str) -> NetworkClassification:
    """识别链接网络上下文。

    Args:
        url: 原始 URL。

    Returns:
        NetworkClassification: 网络上下文分类结果。
    """

    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in {"http", "https"}:
        return NetworkClassification(
            context=scheme or "missing_scheme",
            hint="非 HTTP/HTTPS 链接，默认不检测。",
            is_http=False,
            requires_context=False,
        )

    host = (parts.hostname or "").lower().rstrip(".")
    if not host:
        return NetworkClassification(
            context="unknown_private_context",
            hint="缺少 host，无法可靠判断网络上下文。",
            is_http=True,
            requires_context=True,
        )

    ip_context = classify_ip_host(host)
    if ip_context is not None:
        return ip_context
    if host.endswith(".ts.net"):
        return NetworkClassification(
            context="tailscale",
            hint="Tailscale MagicDNS 域名，需要连接对应 tailnet 后检测。",
            is_http=True,
            requires_context=True,
        )
    if host.endswith(".local") or is_single_label_host(host):
        return NetworkClassification(
            context="private_lan",
            hint="局域网或 mDNS 主机名，需要在对应局域网内检测。",
            is_http=True,
            requires_context=True,
        )
    if host.endswith(CORP_HINT_SUFFIXES):
        return NetworkClassification(
            context="corp_intranet",
            hint="疑似公司或内网域名，需要在公司网络/VPN 环境检测。",
            is_http=True,
            requires_context=True,
        )
    return NetworkClassification(
        context="public_web",
        hint=None,
        is_http=True,
        requires_context=False,
    )


def classify_ip_host(host: str) -> NetworkClassification | None:
    """按 IP 地址识别网络上下文。

    Args:
        host: URL host。

    Returns:
        NetworkClassification | None: IP 地址分类；非 IP host 返回 None。
    """

    try:
        address = ipaddress.ip_address(host.strip("[]"))
    except ValueError:
        return None
    if address in TAILSCALE_CGNAT:
        return NetworkClassification(
            context="tailscale",
            hint="Tailscale 100.64.0.0/10 地址，需要连接对应 tailnet 后检测。",
            is_http=True,
            requires_context=True,
        )
    if address.is_private or address.is_loopback or address.is_link_local:
        return NetworkClassification(
            context="private_lan",
            hint="私有、回环或链路本地地址，需要在对应网络环境检测。",
            is_http=True,
            requires_context=True,
        )
    return NetworkClassification(
        context="public_web",
        hint=None,
        is_http=True,
        requires_context=False,
    )


def is_single_label_host(host: str) -> bool:
    """判断 host 是否是单标签内网主机名。

    Args:
        host: URL host。

    Returns:
        bool: 不含点号且不是纯数字时返回 True。
    """

    return "." not in host and not host.isdigit()


async def _check_one(
    bookmark: Bookmark,
    options: LinkCheckOptions,
    client: httpx.AsyncClient,
    semaphore: asyncio.Semaphore,
    rate_limiter: RequestRateLimiter,
) -> LinkCheckResult:
    """检测单个书签链接。

    Args:
        bookmark: 待检测书签。
        options: 链接检测选项。
        client: HTTPX 异步客户端。
        semaphore: 并发限制信号量。
        rate_limiter: 请求启动限速器。

    Returns:
        LinkCheckResult: 单条检测结果。
    """

    classification = classify_url_network(bookmark.url)
    if not classification.is_http:
        return base_result(bookmark, checked=False, skipped_reason="unsupported_scheme")
    if classification.requires_context and not options.check_private_links:
        return base_result(bookmark, checked=False, skipped_reason="context_required")

    async with semaphore:
        await rate_limiter.wait()
        start = time.perf_counter()
        try:
            async with client.stream("GET", bookmark.url) as response:
                elapsed_ms = int((time.perf_counter() - start) * 1000)
                return base_result(
                    bookmark,
                    checked=True,
                    status_code=response.status_code,
                    final_url=str(response.url),
                    elapsed_ms=elapsed_ms,
                )
        except httpx.TimeoutException as exc:
            return error_result(bookmark, start, "timeout", exc)
        except httpx.TooManyRedirects as exc:
            return error_result(bookmark, start, "too_many_redirects", exc)
        except httpx.InvalidURL as exc:
            return error_result(bookmark, start, "invalid_url", exc)
        except httpx.ConnectError as exc:
            return error_result(bookmark, start, "connect_error", exc)
        except httpx.TransportError as exc:
            return error_result(bookmark, start, "transport_error", exc)
        except ssl.SSLError as exc:
            return error_result(bookmark, start, "ssl_error", exc)


def base_result(bookmark: Bookmark, **overrides: Any) -> LinkCheckResult:
    """构造链接检测结果。

    Args:
        bookmark: 来源书签。
        overrides: 需要覆盖的结果字段。

    Returns:
        LinkCheckResult: 单条链接检测结果。
    """

    values = {
        "order": bookmark.order,
        "title": bookmark.title,
        "url": bookmark.url,
        "folder_path": bookmark.folder_path,
        "checked": False,
        "skipped_reason": None,
        "network_context": classify_url_network(bookmark.url).context,
        "network_hint": classify_url_network(bookmark.url).hint,
        "status_code": None,
        "final_url": None,
        "error_category": None,
        "error_message": None,
        "elapsed_ms": None,
    }
    values.update(overrides)
    return LinkCheckResult(**values)


def error_result(
    bookmark: Bookmark,
    start: float,
    category: str,
    exc: Exception,
) -> LinkCheckResult:
    """构造请求异常结果。

    Args:
        bookmark: 来源书签。
        start: 请求开始时间。
        category: 标准化错误类别。
        exc: 捕获到的异常。

    Returns:
        LinkCheckResult: 带错误类别的检测结果。
    """

    return base_result(
        bookmark,
        checked=True,
        error_category=category,
        error_message=str(exc),
        elapsed_ms=int((time.perf_counter() - start) * 1000),
    )


class RequestRateLimiter:
    """简单的异步请求启动限速器。"""

    def __init__(self, delay: float) -> None:
        """初始化限速器。

        Args:
            delay: 两次请求启动之间的最小秒数。

        Returns:
            None: 初始化方法不返回值。
        """

        self._delay = delay
        self._lock = asyncio.Lock()
        self._last_started_at = 0.0

    async def wait(self) -> None:
        """等待到下一次允许启动请求的时间。

        Args:
            self: 当前限速器实例。

        Returns:
            None: 到达允许启动时间后返回。
        """

        if self._delay <= 0:
            return
        async with self._lock:
            now = time.perf_counter()
            wait_for = self._delay - (now - self._last_started_at)
            if wait_for > 0:
                await asyncio.sleep(wait_for)
            self._last_started_at = time.perf_counter()
