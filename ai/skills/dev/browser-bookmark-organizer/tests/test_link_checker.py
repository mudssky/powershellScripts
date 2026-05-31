import asyncio

import httpx

from browser_bookmark_organizer.link_checker import (
    LinkCheckOptions,
    check_links,
    classify_url_network,
)
from browser_bookmark_organizer.models import Bookmark


def test_check_links_classifies_http_results_and_skips_non_http() -> None:
    """验证链接检测能分类 HTTP 状态、异常和非 HTTP scheme。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    async def handler(request: httpx.Request) -> httpx.Response:
        """模拟 HTTPX 响应。

        Args:
            request: HTTPX 请求对象。

        Returns:
            httpx.Response: 测试用响应；连接错误通过异常表达。
        """

        if request.url.host == "ok.example":
            return httpx.Response(200, request=request)
        if request.url.host == "missing.example":
            return httpx.Response(404, request=request)
        raise httpx.ConnectError("connection failed", request=request)

    bookmarks = [
        Bookmark(title="ok", url="https://ok.example", folder_path=("Root",), order=1),
        Bookmark(title="missing", url="https://missing.example", folder_path=("Root",), order=2),
        Bookmark(title="local", url="file:///tmp/a.txt", folder_path=("Root",), order=3),
        Bookmark(title="error", url="https://error.example", folder_path=("Root",), order=4),
    ]

    results = asyncio.run(
        check_links(
            bookmarks,
            LinkCheckOptions(timeout=1, concurrency=2, delay=0),
            transport=httpx.MockTransport(handler),
        )
    )

    assert [result.order for result in results] == [1, 2, 3, 4]
    assert results[0].status_code == 200
    assert results[1].status_code == 404
    assert results[1].is_problem
    assert results[2].skipped_reason == "unsupported_scheme"
    assert results[3].error_category == "connect_error"


def test_private_and_tailscale_links_are_context_required_by_default() -> None:
    """验证私网和 Tailscale 链接默认不会被当成死链检测。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    bookmarks = [
        Bookmark(title="macmini", url="http://macmini:3000", folder_path=("Home",), order=1),
        Bookmark(title="lan", url="http://192.168.1.10", folder_path=("Home",), order=2),
        Bookmark(
            title="tailnet", url="https://macmini.tailnet.ts.net", folder_path=("Home",), order=3
        ),
        Bookmark(title="tail-ip", url="http://100.64.1.2", folder_path=("Home",), order=4),
        Bookmark(title="corp", url="https://portal.internal", folder_path=("Work",), order=5),
    ]

    results = asyncio.run(check_links(bookmarks, LinkCheckOptions(timeout=1, delay=0)))

    assert [result.checked for result in results] == [False, False, False, False, False]
    assert {result.skipped_reason for result in results} == {"context_required"}
    assert [result.network_context for result in results] == [
        "private_lan",
        "private_lan",
        "tailscale",
        "tailscale",
        "corp_intranet",
    ]
    assert all(not result.is_problem for result in results)


def test_private_links_can_be_checked_explicitly() -> None:
    """验证显式允许后会检测私网类 HTTP 链接。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    async def handler(request: httpx.Request) -> httpx.Response:
        """模拟私网 HTTP 响应。

        Args:
            request: HTTPX 请求对象。

        Returns:
            httpx.Response: 测试用响应。
        """

        return httpx.Response(200, request=request)

    results = asyncio.run(
        check_links(
            [Bookmark(title="macmini", url="http://macmini:3000", folder_path=("Home",), order=1)],
            LinkCheckOptions(timeout=1, delay=0, check_private_links=True),
            transport=httpx.MockTransport(handler),
        )
    )

    assert results[0].checked
    assert results[0].status_code == 200
    assert results[0].network_context == "private_lan"


def test_classify_url_network_identifies_common_contexts() -> None:
    """验证网络上下文分类覆盖常见私网和公网形态。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    assert classify_url_network("https://example.com").context == "public_web"
    assert classify_url_network("http://10.0.0.2").context == "private_lan"
    assert classify_url_network("http://nas.local").context == "private_lan"
    assert classify_url_network("http://macmini").context == "private_lan"
    assert classify_url_network("https://device.tailnet.ts.net").context == "tailscale"
    assert classify_url_network("http://100.100.100.100").context == "tailscale"
    assert classify_url_network("https://service.corp").context == "corp_intranet"
