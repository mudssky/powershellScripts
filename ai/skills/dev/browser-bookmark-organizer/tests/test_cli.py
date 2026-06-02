import json
from pathlib import Path

import pytest

from browser_bookmark_organizer.cli import BackgroundReviewServer, main

FIXTURE = Path(__file__).parent / "fixtures" / "sample_bookmarks.html"


def test_legacy_cli_writes_markdown_html_and_json_outputs(tmp_path: Path) -> None:
    """验证旧版 CLI 入口能写出 Markdown、HTML 与 JSON 报告。

    Args:
        tmp_path: pytest 提供的临时目录。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    exit_code = main([str(FIXTURE), "--output-dir", str(tmp_path)])

    assert exit_code == 0
    markdown = (tmp_path / "bookmark-report.md").read_text(encoding="utf-8")
    html = (tmp_path / "bookmark-report.html").read_text(encoding="utf-8")
    payload = json.loads((tmp_path / "bookmark-report.json").read_text(encoding="utf-8"))
    assert "# 浏览器书签整理报告" in markdown
    assert "BOOKMARK ORGANIZER REPORT" in html
    assert payload["summary"]["bookmarkCount"] == 5
    assert payload["linkChecks"]["enabled"] is False


def test_analyze_command_writes_workspace_files(tmp_path: Path) -> None:
    """验证 analyze 子命令会写入 workspace 标准文件。

    Args:
        tmp_path: pytest 提供的临时目录。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    workspace = tmp_path / "run-001"

    exit_code = main(["analyze", str(FIXTURE), "--workspace", str(workspace), "--no-review"])

    assert exit_code == 0
    assert (workspace / "bookmark-report.md").is_file()
    assert (workspace / "bookmark-report.html").is_file()
    assert (workspace / "snapshot.json").is_file()
    assert (workspace / "operations.jsonl").is_file()
    assert (workspace / "current-tree.json").is_file()
    payload = json.loads((workspace / "analysis.json").read_text(encoding="utf-8"))
    assert payload["summary"]["folderCount"] == 3
    assert payload["summary"]["bookmarkCount"] == 5


def test_apply_ops_tree_status_and_export(tmp_path: Path) -> None:
    """验证 operation replay、目录树、状态和导出链路。

    Args:
        tmp_path: pytest 提供的临时目录。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    workspace = tmp_path / "run-ops"
    ops_path = tmp_path / "ops.json"
    export_path = tmp_path / "cleaned.html"
    operations = [
        {
            "phase": "tree_restructure",
            "op": "create_folder",
            "path": ["Dev", "Python"],
            "reason": "建立 Python 目标目录",
        },
        {
            "phase": "bookmark_assignment",
            "op": "move_bookmark",
            "bookmarkId": "b_000004",
            "toPath": ["Dev", "Python"],
            "reason": "Python 官网移动到 Python 目录",
        },
        {
            "phase": "dead_link_triage",
            "op": "mark_bookmark",
            "bookmarkId": "b_000005",
            "mark": "needs_title_review",
        },
    ]
    ops_path.write_text(
        json.dumps({"operations": operations}, ensure_ascii=False), encoding="utf-8"
    )

    assert main(["analyze", str(FIXTURE), "--workspace", str(workspace), "--no-review"]) == 0
    assert main(["apply-ops", "--workspace", str(workspace), "--input", str(ops_path)]) == 0
    assert main(["tree", "--workspace", str(workspace), "--format", "json"]) == 0
    assert main(["status", "--workspace", str(workspace)]) == 0
    assert main(["export", "--workspace", str(workspace), "--output", str(export_path)]) == 0

    current_tree = json.loads((workspace / "current-tree.json").read_text(encoding="utf-8"))
    operations_log = (workspace / "operations.jsonl").read_text(encoding="utf-8")
    exported = export_path.read_text(encoding="utf-8")
    assert "/Dev/Python" in [folder["displayPath"] for folder in current_tree["folders"]]
    assert "move_bookmark" in operations_log
    assert "Python" in exported


def test_analyze_command_starts_review_by_default_for_workspace(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """验证 workspace 分析默认进入临时 WebUI，并传递自动关停参数。

    Args:
        tmp_path: pytest 提供的临时目录。
        monkeypatch: pytest 提供的 monkeypatch 工具。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    workspace = tmp_path / "run-review"
    calls: list[tuple[Path, str, int, bool, int]] = []

    def fake_start_review_server_background(
        workspace_arg: Path,
        host: str,
        port: int,
        open_browser: bool,
        shutdown_after_seconds: int,
    ) -> BackgroundReviewServer:
        """记录 WebUI 启动参数，避免测试阻塞。

        Args:
            workspace_arg: workspace 路径。
            host: 监听地址。
            port: 监听端口。
            open_browser: 是否自动打开浏览器。
            shutdown_after_seconds: 自动关停秒数。

        Returns:
            BackgroundReviewServer: 伪造的后台服务信息。
        """

        calls.append((workspace_arg, host, port, open_browser, shutdown_after_seconds))
        return BackgroundReviewServer(
            url="http://127.0.0.1:12345",
            pid=123,
            log_path=workspace_arg / "review-server.log",
            pid_path=workspace_arg / "review-server.pid",
            shutdown_after_seconds=shutdown_after_seconds,
        )

    monkeypatch.setattr(
        "browser_bookmark_organizer.cli.start_review_server_background",
        fake_start_review_server_background,
    )

    exit_code = main(
        [
            "analyze",
            str(FIXTURE),
            "--workspace",
            str(workspace),
            "--shutdown-after",
            "5",
        ]
    )

    assert exit_code == 0
    assert calls == [(workspace.resolve(), "127.0.0.1", 0, False, 5)]
    assert (workspace / "analysis.json").is_file()


def test_analyze_command_creates_default_workspace_when_reviewing(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """验证无输出参数时会创建默认 workspace 并启动 WebUI。

    Args:
        tmp_path: pytest 提供的临时目录。
        monkeypatch: pytest 提供的 monkeypatch 工具。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    state_home = tmp_path / "state"
    calls: list[Path] = []

    def fake_start_review_server_background(
        workspace_arg: Path,
        host: str,
        port: int,
        open_browser: bool,
        shutdown_after_seconds: int,
    ) -> BackgroundReviewServer:
        """记录默认 workspace 路径。

        Args:
            workspace_arg: workspace 路径。
            host: 监听地址。
            port: 监听端口。
            open_browser: 是否自动打开浏览器。
            shutdown_after_seconds: 自动关停秒数。

        Returns:
            BackgroundReviewServer: 伪造的后台服务信息。
        """

        calls.append(workspace_arg)
        return BackgroundReviewServer(
            url="http://127.0.0.1:12345",
            pid=123,
            log_path=workspace_arg / "review-server.log",
            pid_path=workspace_arg / "review-server.pid",
            shutdown_after_seconds=shutdown_after_seconds,
        )

    monkeypatch.setenv("XDG_STATE_HOME", str(state_home))
    monkeypatch.setattr(
        "browser_bookmark_organizer.cli.start_review_server_background",
        fake_start_review_server_background,
    )

    exit_code = main(["analyze", str(FIXTURE), "--shutdown-after", "1"])

    assert exit_code == 0
    assert len(calls) == 1
    assert calls[0].parent == state_home / "browser-bookmark-organizer" / "runs"
    assert (calls[0] / "analysis.json").is_file()


def test_analyze_command_foreground_starts_blocking_review_when_requested(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """验证显式 --foreground 时才以前台方式运行 WebUI。

    Args:
        tmp_path: pytest 提供的临时目录。
        monkeypatch: pytest 提供的 monkeypatch 工具。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    workspace = tmp_path / "run-foreground"
    calls: list[tuple[Path, str, int, bool, int, Path | None]] = []

    def fake_run_review_server_foreground(
        workspace_arg: Path,
        host: str,
        port: int,
        open_browser: bool,
        shutdown_after_seconds: int,
        log_file: Path | None = None,
    ) -> None:
        """记录前台 WebUI 启动参数，避免测试阻塞。

        Args:
            workspace_arg: workspace 路径。
            host: 监听地址。
            port: 监听端口。
            open_browser: 是否自动打开浏览器。
            shutdown_after_seconds: 自动关停秒数。
            log_file: 可选服务日志路径。

        Returns:
            None: 只记录调用。
        """

        calls.append((workspace_arg, host, port, open_browser, shutdown_after_seconds, log_file))

    monkeypatch.setattr(
        "browser_bookmark_organizer.cli.run_review_server_foreground",
        fake_run_review_server_foreground,
    )

    exit_code = main(
        [
            "analyze",
            str(FIXTURE),
            "--workspace",
            str(workspace),
            "--foreground",
            "--shutdown-after",
            "5",
        ]
    )

    assert exit_code == 0
    assert calls == [(workspace.resolve(), "127.0.0.1", 0, False, 5, None)]


def test_review_command_defaults_to_background_server(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """验证 review 子命令默认后台启动，避免 agent 被服务阻塞。

    Args:
        tmp_path: pytest 提供的临时目录。
        monkeypatch: pytest 提供的 monkeypatch 工具。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    workspace = tmp_path / "run-review"
    assert main(["analyze", str(FIXTURE), "--workspace", str(workspace), "--no-review"]) == 0
    calls: list[Path] = []

    def fake_start_review_server_background(
        workspace_arg: Path,
        host: str,
        port: int,
        open_browser: bool,
        shutdown_after_seconds: int,
        log_file: Path | None = None,
    ) -> BackgroundReviewServer:
        """记录 review 子命令后台启动参数。

        Args:
            workspace_arg: workspace 路径。
            host: 监听地址。
            port: 监听端口。
            open_browser: 是否自动打开浏览器。
            shutdown_after_seconds: 自动关停秒数。
            log_file: 可选服务日志路径。

        Returns:
            BackgroundReviewServer: 伪造的后台服务信息。
        """

        calls.append(workspace_arg)
        return BackgroundReviewServer(
            url="http://127.0.0.1:23456",
            pid=234,
            log_path=log_file or workspace_arg / "review-server.log",
            pid_path=workspace_arg / "review-server.pid",
            shutdown_after_seconds=shutdown_after_seconds,
        )

    monkeypatch.setattr(
        "browser_bookmark_organizer.cli.start_review_server_background",
        fake_start_review_server_background,
    )

    assert main(["review", "--workspace", str(workspace), "--shutdown-after", "5"]) == 0
    assert calls == [workspace.resolve()]


def test_wait_for_tcp_server_reports_timeout() -> None:
    """验证后台服务就绪等待在超时时返回 False。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    from browser_bookmark_organizer.cli import wait_for_tcp_server

    assert wait_for_tcp_server("127.0.0.1", 9, timeout_seconds=0.01) is False
