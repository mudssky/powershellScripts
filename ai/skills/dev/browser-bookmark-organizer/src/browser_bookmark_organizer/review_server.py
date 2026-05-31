"""本地交互审核服务。"""

from __future__ import annotations

import asyncio
from contextlib import suppress
from dataclasses import dataclass
from datetime import datetime, timedelta
import logging
import socket
import webbrowser
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from browser_bookmark_organizer.clock import now_local
from browser_bookmark_organizer.state import (
    approved_operations,
    build_tree_payload,
    export_netscape_html,
    replay_operations,
)
from browser_bookmark_organizer.templating import package_static_dir, render_template
from browser_bookmark_organizer.workspace import (
    create_decision_payload,
    read_json,
    read_jsonl,
    resolve_workspace,
    write_json,
)

DEFAULT_REVIEW_TTL_SECONDS = 3600
logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class ReviewServerInfo:
    """本地审核服务运行信息。

    Args:
        url: 用户可访问的本地 URL。
        shutdown_after_seconds: 自动关停秒数；0 表示不自动关停。
        expires_at: 自动关停时间；未启用 TTL 时为 None。

    Returns:
        ReviewServerInfo: 服务元数据。
    """

    url: str
    shutdown_after_seconds: int
    expires_at: datetime | None


def create_app(workspace: Path, server_info: ReviewServerInfo | None = None) -> FastAPI:
    """创建本地审核服务应用。

    Args:
        workspace: workspace 根目录。
        server_info: 可选服务运行信息，用于页面提示 URL 和自动关停时间。

    Returns:
        FastAPI: 已配置路由的应用实例。
    """

    paths = resolve_workspace(workspace)
    app = FastAPI(
        title="Bookmark Organizer Review",
        docs_url=None,
        redoc_url=None,
    )
    app.mount("/static", StaticFiles(directory=package_static_dir()), name="static")

    @app.get("/", response_class=HTMLResponse)
    async def index() -> str:
        """返回审核工作台 HTML。

        Args:
            None.

        Returns:
            str: HTML 页面。
        """

        return render_review_html(paths.root, server_info)

    @app.get("/api/analysis")
    async def get_analysis() -> JSONResponse:
        """返回 workspace 分析数据。

        Args:
            None.

        Returns:
            JSONResponse: `analysis.json` 内容。
        """

        if not paths.analysis.is_file():
            raise HTTPException(status_code=404, detail="analysis.json not found")
        payload = read_json(paths.analysis)
        if paths.snapshot.is_file():
            operations = read_jsonl(paths.operations)
            state = replay_operations(read_json(paths.snapshot), approved_operations(operations))
            current_tree = build_tree_payload(state)
            payload["currentTree"] = current_tree
            payload["operations"] = operations
            payload["workspaceStatus"] = {
                "operationCount": len(operations),
                "folderCount": current_tree["folderCount"],
                "bookmarkCount": current_tree["bookmarkCount"],
            }
        return JSONResponse(payload)

    @app.get("/api/decisions")
    async def get_decisions() -> JSONResponse:
        """返回已保存的用户选择。

        Args:
            None.

        Returns:
            JSONResponse: `decisions.json` 内容；不存在时返回空选择。
        """

        if not paths.decisions.is_file():
            return JSONResponse({"schemaVersion": 1, "decisions": {}})
        return JSONResponse(read_json(paths.decisions))

    @app.post("/api/decisions")
    async def save_decisions(request: Request) -> JSONResponse:
        """保存用户选择。

        Args:
            request: FastAPI 请求对象，body 应为 JSON。

        Returns:
            JSONResponse: 保存结果和目标文件路径。
        """

        body: dict[str, Any] = await request.json()
        decisions = body.get("decisions", body)
        if not isinstance(decisions, dict):
            raise HTTPException(status_code=400, detail="decisions must be an object")
        payload = create_decision_payload(decisions)
        write_json(paths.decisions, payload)
        logger.info("Saved review decisions path=%s", paths.decisions)
        return JSONResponse({"ok": True, "path": str(paths.decisions)})

    @app.post("/api/export")
    async def export_current_bookmarks() -> JSONResponse:
        """导出当前已批准状态为新的 bookmarks HTML。

        Args:
            None.

        Returns:
            JSONResponse: 导出结果和输出文件路径。
        """

        if not paths.snapshot.is_file():
            raise HTTPException(status_code=404, detail="snapshot.json not found")
        state = replay_operations(
            read_json(paths.snapshot), approved_operations(read_jsonl(paths.operations))
        )
        paths.cleaned_html.write_text(export_netscape_html(state), encoding="utf-8")
        logger.info("Exported cleaned bookmarks path=%s", paths.cleaned_html)
        return JSONResponse({"ok": True, "path": str(paths.cleaned_html)})

    @app.get("/api/server")
    async def get_server_info() -> JSONResponse:
        """返回本地服务运行信息。

        Args:
            None.

        Returns:
            JSONResponse: 服务 URL 与自动关停信息。
        """

        return JSONResponse(server_info_to_payload(server_info))

    return app


def run_review_server(
    workspace: Path,
    host: str,
    port: int,
    open_browser: bool,
    shutdown_after_seconds: int = DEFAULT_REVIEW_TTL_SECONDS,
) -> None:
    """启动本地审核服务。

    Args:
        workspace: workspace 根目录。
        host: 监听地址，默认应为 127.0.0.1。
        port: 监听端口；0 表示自动选择空闲端口。
        open_browser: 是否自动打开浏览器。
        shutdown_after_seconds: 自动关停秒数；0 表示不自动关停。

    Returns:
        None: 服务运行到用户中断。
    """

    selected_port = find_available_port(host) if port == 0 else port
    url = f"http://{host}:{selected_port}"
    expires_at = (
        now_local() + timedelta(seconds=shutdown_after_seconds)
        if shutdown_after_seconds > 0
        else None
    )
    server_info = ReviewServerInfo(
        url=url,
        shutdown_after_seconds=shutdown_after_seconds,
        expires_at=expires_at,
    )
    if open_browser:
        webbrowser.open(url)
    logger.info(
        "Review UI running url=%s workspace=%s shutdown_after=%s",
        url,
        workspace,
        shutdown_after_seconds,
    )
    print(f"Review UI: {url}", flush=True)
    if shutdown_after_seconds > 0:
        print(f"Auto shutdown: {format_duration(shutdown_after_seconds)}", flush=True)
    else:
        print("Auto shutdown: disabled", flush=True)
    print("Press Ctrl+C to stop.")
    asyncio.run(
        serve_with_shutdown_timer(
            create_app(workspace, server_info), host, selected_port, shutdown_after_seconds
        )
    )


async def serve_with_shutdown_timer(
    app: FastAPI,
    host: str,
    port: int,
    shutdown_after_seconds: int,
) -> None:
    """运行 uvicorn 服务，并按 TTL 自动关停。

    Args:
        app: FastAPI 应用。
        host: 监听地址。
        port: 监听端口。
        shutdown_after_seconds: 自动关停秒数；0 表示不自动关停。

    Returns:
        None: 服务停止后返回。
    """

    config = uvicorn.Config(app, host=host, port=port, log_level="info")
    server = uvicorn.Server(config)
    serve_task = asyncio.create_task(server.serve())
    timer_task: asyncio.Task[None] | None = None
    if shutdown_after_seconds > 0:
        timer_task = asyncio.create_task(stop_server_after(server, shutdown_after_seconds))
    try:
        await serve_task
    finally:
        if timer_task is not None:
            timer_task.cancel()
            with suppress(asyncio.CancelledError):
                await timer_task


async def stop_server_after(server: uvicorn.Server, seconds: int) -> None:
    """等待指定时间后请求 uvicorn 退出。

    Args:
        server: uvicorn 服务实例。
        seconds: 等待秒数。

    Returns:
        None: 设置退出标记后返回。
    """

    await asyncio.sleep(seconds)
    logger.info("Review UI auto stopped after %s.", format_duration(seconds))
    print(f"Review UI auto stopped after {format_duration(seconds)}.", flush=True)
    server.should_exit = True


def server_info_to_payload(server_info: ReviewServerInfo | None) -> dict[str, object]:
    """把服务运行信息转换为模板和 API 共享 payload。

    Args:
        server_info: 可选服务运行信息。

    Returns:
        dict[str, object]: JSON 友好的服务运行信息。
    """

    if server_info is None:
        return {"url": "", "shutdownAfterSeconds": 0, "expiresAt": None}
    return {
        "url": server_info.url,
        "shutdownAfterSeconds": server_info.shutdown_after_seconds,
        "expiresAt": server_info.expires_at.isoformat()
        if server_info.expires_at is not None
        else None,
    }


def format_duration(seconds: int) -> str:
    """格式化秒数为可读时长。

    Args:
        seconds: 秒数。

    Returns:
        str: 可读时长。
    """

    if seconds < 60:
        return f"{seconds}s"
    minutes, remaining_seconds = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m{remaining_seconds}s" if remaining_seconds else f"{minutes}m"
    hours, remaining_minutes = divmod(minutes, 60)
    if remaining_minutes:
        return f"{hours}h{remaining_minutes}m"
    return f"{hours}h"


def find_available_port(host: str) -> int:
    """查找本机空闲端口。

    Args:
        host: 绑定地址。

    Returns:
        int: 可用端口。
    """

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        return int(sock.getsockname()[1])


def render_review_html(workspace: Path, server_info: ReviewServerInfo | None = None) -> str:
    """渲染审核工作台 HTML。

    Args:
        workspace: workspace 根目录。
        server_info: 可选服务运行信息。

    Returns:
        str: 完整 HTML 页面。
    """

    return render_template(
        "review.html",
        workspace=str(workspace),
        server_info=server_info_to_payload(server_info),
    )
