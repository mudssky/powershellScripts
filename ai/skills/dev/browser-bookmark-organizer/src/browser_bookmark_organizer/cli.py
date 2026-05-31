"""浏览器书签整理 CLI。"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from browser_bookmark_organizer.analysis import analyze_bookmarks
from browser_bookmark_organizer.clock import filesystem_timestamp
from browser_bookmark_organizer.link_checker import LinkCheckOptions, check_links
from browser_bookmark_organizer.parser import parse_bookmark_file
from browser_bookmark_organizer.report import (
    build_report_payload,
    render_html_report,
    render_markdown_report,
)
from browser_bookmark_organizer.review_server import (
    DEFAULT_REVIEW_TTL_SECONDS,
    find_available_port,
    format_duration,
    run_review_server,
)
from browser_bookmark_organizer.state import (
    approved_operations,
    build_snapshot,
    build_tree_payload,
    export_netscape_html,
    normalize_operation,
    render_tree_markdown,
    replay_operations,
)
from browser_bookmark_organizer.workspace import (
    append_jsonl,
    ensure_workspace,
    read_json,
    read_jsonl,
    resolve_workspace,
    write_json,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class BackgroundReviewServer:
    """后台 WebUI 服务启动信息。

    Args:
        url: 可访问的本地 URL。
        pid: 后台进程 PID。
        log_path: 后台服务日志路径。
        pid_path: 后台服务 PID 文件路径。
        shutdown_after_seconds: 自动关停秒数；0 表示不自动关停。

    Returns:
        BackgroundReviewServer: 后台服务启动信息。
    """

    url: str
    pid: int
    log_path: Path
    pid_path: Path
    shutdown_after_seconds: int


def build_arg_parser() -> argparse.ArgumentParser:
    """创建命令行参数解析器。

    Args:
        None.

    Returns:
        argparse.ArgumentParser: 已配置的 CLI 参数解析器。
    """

    parser = argparse.ArgumentParser(
        prog="browser-bookmark-organizer",
        description="Analyze Netscape bookmark HTML exports and optionally review results locally.",
    )
    subparsers = parser.add_subparsers(dest="command")

    analyze_parser = subparsers.add_parser("analyze", help="解析书签并生成 workspace 报告。")
    add_analyze_arguments(analyze_parser)

    review_parser = subparsers.add_parser("review", help="启动本地交互审核页面。")
    review_parser.add_argument(
        "--workspace", required=True, help="包含 analysis.json 的 workspace 目录。"
    )
    review_parser.add_argument("--host", default="127.0.0.1", help="监听地址，默认只绑定本机。")
    review_parser.add_argument("--port", type=int, default=0, help="监听端口；0 表示自动选择。")
    review_parser.add_argument("--open", action="store_true", help="启动后自动打开浏览器。")
    review_parser.add_argument(
        "--foreground",
        action="store_true",
        help="以前台方式运行服务；默认后台启动并立即返回 URL。",
    )
    review_parser.add_argument(
        "--log-file",
        help="服务日志路径；后台启动时默认写入 workspace/review-server.log。",
    )
    review_parser.add_argument(
        "--shutdown-after",
        type=int,
        default=DEFAULT_REVIEW_TTL_SECONDS,
        help="自动关闭服务的秒数；默认 3600，0 表示不自动关闭。",
    )

    tree_parser = subparsers.add_parser("tree", help="输出当前目录树。")
    tree_parser.add_argument("--workspace", required=True, help="workspace 目录。")
    tree_parser.add_argument("--format", choices=("markdown", "json"), default="markdown")

    status_parser = subparsers.add_parser("status", help="输出当前整理状态摘要。")
    status_parser.add_argument("--workspace", required=True, help="workspace 目录。")

    apply_parser = subparsers.add_parser("apply-ops", help="验证并追加已批准 operations。")
    apply_parser.add_argument("--workspace", required=True, help="workspace 目录。")
    apply_parser.add_argument(
        "--ops-file",
        "--input",
        dest="ops_file",
        required=True,
        help="operation JSON 或 JSONL 文件。",
    )
    apply_parser.add_argument(
        "--dry-run", action="store_true", help="只验证，不写入 operations.jsonl。"
    )

    export_parser = subparsers.add_parser("export", help="导出新的 Netscape Bookmark HTML。")
    export_parser.add_argument("--workspace", required=True, help="workspace 目录。")
    export_parser.add_argument(
        "--output", help="输出 HTML 文件；默认写入 workspace/bookmarks.cleaned.html。"
    )

    return parser


def add_analyze_arguments(parser: argparse.ArgumentParser) -> None:
    """给 analyze 子命令添加参数。

    Args:
        parser: argparse 子命令解析器。

    Returns:
        None: 直接修改解析器。
    """

    parser.add_argument("input", help="浏览器导出的 Netscape Bookmark HTML 文件。")
    parser.add_argument("--workspace", help="输出 workspace 目录。")
    parser.add_argument(
        "--output-dir",
        help="兼容旧参数；会生成 bookmark-report.md/html/json。",
    )
    parser.add_argument("--markdown-out", help="Markdown 报告输出路径。")
    parser.add_argument("--json-out", help="JSON 数据输出路径。")
    parser.add_argument("--html-out", help="HTML 报告输出路径。")
    parser.add_argument(
        "--review",
        dest="review",
        action="store_true",
        default=None,
        help="分析完成后启动本地 WebUI。",
    )
    parser.add_argument(
        "--no-review",
        dest="review",
        action="store_false",
        help="只写入报告和 workspace，不启动 WebUI。",
    )
    parser.add_argument("--host", default="127.0.0.1", help="WebUI 监听地址，默认只绑定本机。")
    parser.add_argument("--port", type=int, default=0, help="WebUI 监听端口；0 表示自动选择。")
    parser.add_argument("--open", action="store_true", help="WebUI 启动后自动打开浏览器。")
    parser.add_argument(
        "--foreground",
        action="store_true",
        help="以前台方式运行 WebUI；默认后台启动并立即返回 URL。",
    )
    parser.add_argument(
        "--shutdown-after",
        type=int,
        default=DEFAULT_REVIEW_TTL_SECONDS,
        help="WebUI 自动关闭秒数；默认 3600，0 表示不自动关闭。",
    )
    add_link_check_arguments(parser)


def add_link_check_arguments(parser: argparse.ArgumentParser) -> None:
    """添加链接检测参数。

    Args:
        parser: argparse 解析器。

    Returns:
        None: 直接修改解析器。
    """

    parser.add_argument(
        "--check-links",
        action="store_true",
        help="启用 HTTP/HTTPS 链接检测。",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="单个请求超时秒数。",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=32,
        help="链接检测最大并发数。",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.2,
        help="请求启动间隔秒数。",
    )
    parser.add_argument("--max-links", type=int, help="最多检测的 HTTP/HTTPS 链接数量。")
    parser.add_argument(
        "--check-private-links",
        action="store_true",
        help="检测局域网、Tailscale 和公司内网候选链接；默认只标记为需要上下文。",
    )
    parser.add_argument(
        "--network-context",
        default="default",
        help="本次检测所处网络环境标签，例如 home、office、tailscale。",
    )
    parser.add_argument(
        "--no-follow-redirects",
        action="store_true",
        help="链接检测时不跟随 HTTP 重定向。",
    )


def main(argv: list[str] | None = None) -> int:
    """运行浏览器书签整理 CLI。

    Args:
        argv: 可选命令行参数；None 表示读取 `sys.argv`。

    Returns:
        int: 退出码。0 表示成功，1 表示运行时错误，argparse 参数错误使用 2。
    """

    parser = build_arg_parser()
    argv = normalize_argv(argv)
    args = parser.parse_args(argv)

    try:
        if args.command == "review":
            return run_review_command(args)
        if args.command == "analyze":
            return run_analyze_command(args)
        if args.command == "tree":
            return run_tree_command(args)
        if args.command == "status":
            return run_status_command(args)
        if args.command == "apply-ops":
            return run_apply_ops_command(args)
        if args.command == "export":
            return run_export_command(args)
        parser.print_help()
        return 0
    except OSError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1


def normalize_argv(argv: list[str] | None) -> list[str] | None:
    """兼容旧版直接传入 HTML 文件的入口。

    Args:
        argv: 原始命令行参数；None 表示读取 `sys.argv`。

    Returns:
        list[str] | None: 如果是旧入口，则自动补上 `analyze` 子命令。
    """

    raw_args = sys.argv[1:] if argv is None else list(argv)
    if not raw_args:
        return raw_args
    first = raw_args[0]
    if first in {"analyze", "review", "tree", "status", "apply-ops", "export", "-h", "--help"}:
        return raw_args
    return ["analyze", *raw_args]


def make_link_progress_writer(progress_path: Path | None):
    """创建链接检测进度回调函数。

    每完成一个检测后写入进度文件，供 WebUI 轮询。

    Args:
        progress_path: 进度文件路径；为 None 时返回空回调。

    Returns:
        Callable: 进度回调函数 (done, total, results) -> None。
    """

    if progress_path is None:
        return lambda done, total, results: None

    from browser_bookmark_organizer.report import link_status_bucket

    def write_progress(done: int, total: int, results: list) -> None:
        """写入进度 JSON。

        Args:
            done: 已完成数量。
            total: 总数量。
            results: 已完成的检测结果列表。
        """
        status_summary: dict[str, int] = {}
        problem_items = []
        for r in results[-20:]:
            bucket = link_status_bucket(r)
            status_summary[bucket] = status_summary.get(bucket, 0) + 1
            if r.is_problem or r.skipped_reason == "context_required":
                problem_items.append(
                    {
                        "title": r.title,
                        "url": r.url,
                        "bucket": bucket,
                        "statusCode": r.status_code,
                        "errorCategory": r.error_category,
                    }
                )
        payload = {
            "running": True,
            "done": done,
            "total": total,
            "percent": round(done / total * 100, 1) if total > 0 else 0,
            "statusSummary": status_summary,
            "recentProblems": problem_items[-10:],
        }
        progress_path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")

    return write_progress


def run_analyze_command(args: argparse.Namespace) -> int:
    """执行书签分析命令。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。0 表示成功，1 表示运行时错误。
    """

    input_path = Path(args.input).expanduser().resolve()
    validate_analyze_args(input_path, args)
    review_enabled = should_start_review_after_analyze(args)
    if review_enabled:
        validate_review_server_args(args.host, args.port, args.shutdown_after)
        if not args.workspace:
            args.workspace = str(default_workspace_path(input_path))
    root = parse_bookmark_file(input_path)
    analysis = analyze_bookmarks(root, input_path)

    link_options: LinkCheckOptions | None = None
    link_results = None
    if args.check_links:
        link_options = LinkCheckOptions(
            timeout=args.timeout,
            follow_redirects=not args.no_follow_redirects,
            concurrency=args.concurrency,
            delay=args.delay,
            max_links=args.max_links,
            check_private_links=args.check_private_links,
            network_context=args.network_context,
        )
        workspace_dir = Path(args.workspace).expanduser().resolve() if args.workspace else None
        progress_path = resolve_workspace(workspace_dir).link_progress if workspace_dir else None
        link_results = asyncio.run(
            check_links(
                analysis.bookmarks,
                link_options,
                on_progress=make_link_progress_writer(progress_path),
            )
        )
        # 检测完成，标记进度为已完成
        if progress_path and progress_path.is_file():
            progress_path.write_text(
                json.dumps(
                    {
                        "running": False,
                        "done": len(link_results),
                        "total": len(link_results),
                        "percent": 100,
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

    payload = build_report_payload(analysis, link_results, link_options)
    markdown = render_markdown_report(analysis, link_results, link_options)
    html = render_html_report(payload)
    snapshot = build_snapshot(root, str(input_path))
    write_analyze_outputs(markdown, html, payload, snapshot, args)
    if args.workspace:
        print(f"Workspace: {Path(args.workspace).expanduser().resolve()}", flush=True)
    if review_enabled:
        workspace = Path(args.workspace).expanduser().resolve()
        if args.foreground:
            run_review_server_foreground(
                workspace,
                args.host,
                args.port,
                args.open,
                args.shutdown_after,
                None,
            )
        else:
            server = start_review_server_background(
                workspace, args.host, args.port, args.open, args.shutdown_after
            )
            print_background_review_server(server)
    return 0


def run_review_command(args: argparse.Namespace) -> int:
    """执行本地审核服务命令。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。用户中断服务也视为成功。
    """

    workspace = Path(args.workspace).expanduser().resolve()
    if not (workspace / "analysis.json").is_file():
        raise ValueError(f"workspace 缺少 analysis.json，请先运行 analyze: {workspace}")
    validate_review_server_args(args.host, args.port, args.shutdown_after)
    if not args.foreground:
        log_file = Path(args.log_file).expanduser().resolve() if args.log_file else None
        server = start_review_server_background(
            workspace,
            args.host,
            args.port,
            args.open,
            args.shutdown_after,
            log_file,
        )
        print_background_review_server(server)
        return 0
    log_file = Path(args.log_file).expanduser().resolve() if args.log_file else None
    run_review_server_foreground(
        workspace,
        args.host,
        args.port,
        args.open,
        args.shutdown_after,
        log_file,
    )
    return 0


def run_review_server_foreground(
    workspace: Path,
    host: str,
    port: int,
    open_browser: bool,
    shutdown_after_seconds: int,
    log_file: Path | None = None,
) -> None:
    """以前台方式运行本地审核服务。

    Args:
        workspace: workspace 根目录。
        host: 监听地址。
        port: 监听端口；0 表示自动选择。
        open_browser: 是否自动打开浏览器。
        shutdown_after_seconds: 自动关停秒数。
        log_file: 可选服务日志路径；None 表示写到 stderr。

    Returns:
        None: 服务停止后返回。
    """

    configure_logging(log_file)
    logger.info(
        "Starting review server workspace=%s host=%s port=%s shutdown_after=%s",
        workspace,
        host,
        port,
        shutdown_after_seconds,
    )
    try:
        run_review_server(workspace, host, port, open_browser, shutdown_after_seconds)
    except KeyboardInterrupt:
        logger.info("Review server stopped by keyboard interrupt")
        print("Review UI stopped.")


def configure_logging(log_file: Path | None = None) -> None:
    """配置本地服务日志。

    Args:
        log_file: 可选日志文件路径；None 表示写入 stderr。

    Returns:
        None: logging 配置完成后返回。
    """

    handlers: list[logging.Handler]
    if log_file is None:
        handlers = [logging.StreamHandler()]
    else:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers = [logging.FileHandler(log_file, encoding="utf-8")]
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        handlers=handlers,
        force=True,
    )


def _read_saved_port(port_path: Path) -> int | None:
    """读取上一次保存的服务端口。

    Args:
        port_path: 端口文件路径。

    Returns:
        int | None: 有效端口号；不存在或无效时返回 None。
    """

    try:
        if port_path.is_file():
            return int(port_path.read_text(encoding="utf-8").strip())
    except (ValueError, OSError):
        pass
    return None


def _is_port_reachable(host: str, port: int) -> bool:
    """检查端口是否可连接（已有服务在监听）。

    Args:
        host: 监听地址。
        port: 端口号。

    Returns:
        bool: 可连接返回 True。
    """

    import socket as _socket

    try:
        with _socket.create_connection((host, port), timeout=0.5):
            return True
    except (OSError, TimeoutError):
        return False


def start_review_server_background(
    workspace: Path,
    host: str,
    port: int,
    open_browser: bool,
    shutdown_after_seconds: int,
    log_file: Path | None = None,
) -> BackgroundReviewServer:
    """后台启动本地审核服务并立即返回。

    Args:
        workspace: workspace 根目录。
        host: 监听地址。
        port: 监听端口；0 表示自动选择。
        open_browser: 是否自动打开浏览器。
        shutdown_after_seconds: 自动关停秒数。
        log_file: 可选服务日志路径；None 表示写入 workspace/review-server.log。

    Returns:
        BackgroundReviewServer: 后台服务启动信息。
    """

    paths = resolve_workspace(workspace)
    # 端口复用：检查已保存的端口是否仍可用
    saved_port = _read_saved_port(paths.server_port)
    if port == 0 and saved_port is not None and _is_port_reachable(host, saved_port):
        url = f"http://{host}:{saved_port}"
        logger.info("复用已有 review 服务 url=%s", url)
        return BackgroundReviewServer(
            url=url,
            pid=None,
            log_path=log_file or workspace / "review-server.log",
            pid_path=workspace / "review-server.pid",
            shutdown_after_seconds=shutdown_after_seconds,
        )
    selected_port = find_available_port(host) if port == 0 else port
    url = f"http://{host}:{selected_port}"
    # 保存端口供下次复用
    if port == 0:
        paths.server_port.write_text(str(selected_port), encoding="utf-8")
    log_path = log_file or workspace / "review-server.log"
    pid_path = workspace / "review-server.pid"
    command = [
        sys.executable,
        "-m",
        "browser_bookmark_organizer.cli",
        "review",
        "--workspace",
        str(workspace),
        "--host",
        host,
        "--port",
        str(selected_port),
        "--shutdown-after",
        str(shutdown_after_seconds),
        "--foreground",
        "--log-file",
        str(log_path),
    ]
    if open_browser:
        command.append("--open")

    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_stream = log_path.open("a", encoding="utf-8")
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=log_stream,
            stderr=subprocess.STDOUT,
            cwd=Path.cwd(),
            start_new_session=True,
        )
    finally:
        log_stream.close()
    ready = wait_for_tcp_server(host, selected_port, timeout_seconds=10.0)
    if not ready and process.poll() is not None:
        raise ValueError(f"review 服务启动失败，请查看日志: {log_path}")
    pid_path.write_text(f"{process.pid}\n", encoding="utf-8")
    return BackgroundReviewServer(
        url=url,
        pid=process.pid,
        log_path=log_path,
        pid_path=pid_path,
        shutdown_after_seconds=shutdown_after_seconds,
    )


def wait_for_tcp_server(host: str, port: int, timeout_seconds: float) -> bool:
    """等待后台服务完成 TCP 监听。

    Args:
        host: 监听地址。
        port: 监听端口。
        timeout_seconds: 最长等待秒数。

    Returns:
        bool: 端口可连接返回 True，超时返回 False。
    """

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def print_background_review_server(server: BackgroundReviewServer) -> None:
    """输出后台 WebUI 服务信息。

    Args:
        server: 后台服务启动信息。

    Returns:
        None: 信息写入 stdout。
    """

    print(f"Review UI: {server.url}", flush=True)
    print(f"Review PID: {server.pid}", flush=True)
    print(f"Review log: {server.log_path}", flush=True)
    print(f"Review pid file: {server.pid_path}", flush=True)
    if server.shutdown_after_seconds > 0:
        print(f"Auto shutdown: {format_duration(server.shutdown_after_seconds)}", flush=True)
    else:
        print("Auto shutdown: disabled", flush=True)
    print("Service is running in the background. Use --foreground to block in this terminal.")


def run_tree_command(args: argparse.Namespace) -> int:
    """输出当前目录树。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。0 表示成功。
    """

    state = load_current_state(Path(args.workspace))
    tree_payload = build_tree_payload(state)
    if args.format == "json":
        print(json.dumps(tree_payload, ensure_ascii=False, indent=2))
    else:
        print(render_tree_markdown(tree_payload), end="")
    return 0


def run_status_command(args: argparse.Namespace) -> int:
    """输出当前 workspace 状态摘要。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。0 表示成功。
    """

    paths = resolve_workspace(args.workspace)
    state = load_current_state(paths.root)
    tree_payload = build_tree_payload(state)
    operations = read_jsonl(paths.operations)
    payload = {
        "workspace": str(paths.root),
        "folderCount": tree_payload["folderCount"],
        "bookmarkCount": tree_payload["bookmarkCount"],
        "operationCount": len(operations),
        "operationsPath": str(paths.operations),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def run_apply_ops_command(args: argparse.Namespace) -> int:
    """验证并追加 operations。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。0 表示成功。
    """

    paths = resolve_workspace(args.workspace)
    existing_operations = read_jsonl(paths.operations)
    incoming = [
        normalize_operation(operation, index)
        for index, operation in enumerate(load_operations_file(Path(args.ops_file)), start=1)
    ]
    snapshot = read_json(paths.snapshot)
    replay_operations(snapshot, approved_operations([*existing_operations, *incoming]))
    if not args.dry_run:
        append_jsonl(paths.operations, incoming)
        write_current_tree(paths.root)
    print(
        json.dumps(
            {"ok": True, "dryRun": args.dry_run, "operationCount": len(incoming)},
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def run_export_command(args: argparse.Namespace) -> int:
    """导出当前状态为 Netscape Bookmark HTML。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        int: 退出码。0 表示成功。
    """

    paths = resolve_workspace(args.workspace)
    state = load_current_state(paths.root)
    output = Path(args.output).expanduser().resolve() if args.output else paths.cleaned_html
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(export_netscape_html(state), encoding="utf-8")
    print(str(output))
    return 0


def validate_analyze_args(input_path: Path, args: argparse.Namespace) -> None:
    """校验分析参数。

    Args:
        input_path: 已解析的输入路径。
        args: argparse 解析后的参数对象。

    Returns:
        None: 参数合法时返回；非法时抛出 ValueError。
    """

    if not input_path.is_file():
        raise ValueError(f"输入文件不存在: {input_path}")
    if args.timeout <= 0:
        raise ValueError("--timeout 必须大于 0")
    if args.concurrency <= 0:
        raise ValueError("--concurrency 必须大于 0")
    if args.delay < 0:
        raise ValueError("--delay 不能为负数")
    if args.max_links is not None and args.max_links <= 0:
        raise ValueError("--max-links 必须大于 0")
    if not args.network_context.strip():
        raise ValueError("--network-context 不能为空")
    if args.port < 0 or args.port > 65535:
        raise ValueError("--port 必须在 0 到 65535 之间")
    if args.shutdown_after < 0:
        raise ValueError("--shutdown-after 不能为负数")


def validate_review_server_args(host: str, port: int, shutdown_after: int) -> None:
    """校验本地 WebUI 服务参数。

    Args:
        host: 监听地址。
        port: 监听端口；0 表示自动选择。
        shutdown_after: 自动关停秒数；0 表示不自动关停。

    Returns:
        None: 参数合法时返回；非法时抛出 ValueError。
    """

    if host != "127.0.0.1":
        raise ValueError(
            "review 服务默认只建议绑定 127.0.0.1；如确需开放网络，请修改代码后自行承担风险"
        )
    if port < 0 or port > 65535:
        raise ValueError("--port 必须在 0 到 65535 之间")
    if shutdown_after < 0:
        raise ValueError("--shutdown-after 不能为负数")


def should_start_review_after_analyze(args: argparse.Namespace) -> bool:
    """判断 analyze 完成后是否启动 WebUI。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        bool: True 表示启动本地 WebUI。
    """

    if args.review is not None:
        return bool(args.review)
    explicit_file_outputs = any([args.output_dir, args.markdown_out, args.json_out, args.html_out])
    return not explicit_file_outputs


def default_workspace_path(input_path: Path) -> Path:
    """生成默认 workspace 路径。

    Args:
        input_path: 原始书签 HTML 路径。

    Returns:
        Path: 位于用户本机 state 目录下的默认 workspace。
    """

    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    timestamp = filesystem_timestamp()
    stem = slugify_path_part(input_path.stem) or "bookmarks"
    return state_home.expanduser() / "browser-bookmark-organizer" / "runs" / f"{stem}-{timestamp}"


def slugify_path_part(value: str) -> str:
    """把任意文件名片段转换为适合路径的短标识。

    Args:
        value: 原始文件名片段。

    Returns:
        str: 只包含字母、数字、下划线和连字符的标识。
    """

    chars: list[str] = []
    last_was_dash = False
    for char in value:
        if char.isalnum() or char in {"_", "-"}:
            chars.append(char)
            last_was_dash = False
        elif not last_was_dash:
            chars.append("-")
            last_was_dash = True
    return "".join(chars).strip("-_")[:80]


def write_analyze_outputs(
    markdown: str,
    html: str,
    payload: dict[str, object],
    snapshot: dict[str, object],
    args: argparse.Namespace,
) -> None:
    """写入分析输出。

    Args:
        markdown: Markdown 报告文本。
        html: HTML 报告文本。
        payload: JSON 友好的报告数据。
        snapshot: 原始解析快照。
        args: argparse 解析后的参数对象。

    Returns:
        None: 写入完成后返回。
    """

    markdown_out, html_out, json_out = resolve_output_paths(args)
    if markdown_out:
        markdown_out.parent.mkdir(parents=True, exist_ok=True)
        markdown_out.write_text(markdown, encoding="utf-8")
    else:
        print(markdown, end="")

    if html_out:
        html_out.parent.mkdir(parents=True, exist_ok=True)
        html_out.write_text(html, encoding="utf-8")

    if json_out:
        write_json(json_out, payload)
    if args.workspace:
        paths = resolve_workspace(args.workspace)
        write_json(paths.snapshot, snapshot)
        if not paths.operations.exists():
            paths.operations.write_text("", encoding="utf-8")
        write_current_tree(paths.root)


def resolve_output_paths(args: argparse.Namespace) -> tuple[Path | None, Path | None, Path | None]:
    """解析输出文件路径。

    Args:
        args: argparse 解析后的参数对象。

    Returns:
        tuple[Path | None, Path | None, Path | None]: Markdown、HTML、JSON 输出路径。
    """

    markdown_out = Path(args.markdown_out).expanduser().resolve() if args.markdown_out else None
    html_out = Path(args.html_out).expanduser().resolve() if args.html_out else None
    json_out = Path(args.json_out).expanduser().resolve() if args.json_out else None

    if args.workspace:
        paths = resolve_workspace(args.workspace)
        ensure_workspace(paths)
        markdown_out = paths.markdown_report
        html_out = paths.html_report
        json_out = paths.analysis
    elif args.output_dir:
        output_dir = Path(args.output_dir).expanduser().resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        markdown_out = output_dir / "bookmark-report.md"
        html_out = output_dir / "bookmark-report.html"
        json_out = output_dir / "bookmark-report.json"
    return markdown_out, html_out, json_out


def load_current_state(workspace: Path | str) -> dict[str, object]:
    """读取 workspace 并 replay 当前状态。

    Args:
        workspace: workspace 目录。

    Returns:
        dict[str, object]: 当前状态。
    """

    paths = resolve_workspace(workspace)
    if not paths.snapshot.is_file():
        raise ValueError(f"workspace 缺少 snapshot.json，请先运行 analyze: {paths.root}")
    snapshot = read_json(paths.snapshot)
    operations = approved_operations(read_jsonl(paths.operations))
    return replay_operations(snapshot, operations)


def write_current_tree(workspace: Path | str) -> None:
    """写入当前目录树派生文件。

    Args:
        workspace: workspace 目录。

    Returns:
        None: 写入完成后返回。
    """

    paths = resolve_workspace(workspace)
    state = load_current_state(paths.root)
    write_json(paths.current_tree, build_tree_payload(state))


def load_operations_file(path: Path) -> list[dict[str, object]]:
    """读取 operation JSON 或 JSONL 文件。

    Args:
        path: operation 输入文件。

    Returns:
        list[dict[str, object]]: operation 列表。
    """

    if not path.is_file():
        raise ValueError(f"operation 文件不存在: {path}")
    if path.suffix.lower() == ".jsonl":
        return read_jsonl(path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and isinstance(payload.get("operations"), list):
        payload = payload["operations"]
    if not isinstance(payload, list) or not all(isinstance(item, dict) for item in payload):
        raise ValueError("operation JSON 必须是数组，或包含 operations 数组")
    return payload


if __name__ == "__main__":
    raise SystemExit(main())
