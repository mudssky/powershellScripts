"""书签整理 workspace 读写。"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from browser_bookmark_organizer.clock import now_local_iso


@dataclass(frozen=True, slots=True)
class WorkspacePaths:
    """workspace 内部文件路径集合。

    Args:
        root: workspace 根目录。
        analysis: 分析 JSON 路径。
        snapshot: 原始解析快照路径。
        operations: 已批准操作 JSONL 路径。
        current_tree: 当前目录树派生 JSON 路径。
        cleaned_html: 导出的新书签 HTML 路径。
        markdown_report: Markdown 报告路径。
        html_report: HTML 报告路径。
        decisions: 用户选择 JSON 路径。
        link_progress: 链接检测进度 JSON 路径。

    Returns:
        WorkspacePaths: workspace 文件路径集合。
    """

    root: Path
    analysis: Path
    snapshot: Path
    operations: Path
    current_tree: Path
    cleaned_html: Path
    markdown_report: Path
    html_report: Path
    decisions: Path
    link_progress: Path
    server_port: Path


def resolve_workspace(path: str | Path) -> WorkspacePaths:
    """解析 workspace 路径。

    Args:
        path: 用户指定的 workspace 目录。

    Returns:
        WorkspacePaths: workspace 文件路径集合。
    """

    root = Path(path).expanduser().resolve()
    return WorkspacePaths(
        root=root,
        analysis=root / "analysis.json",
        snapshot=root / "snapshot.json",
        operations=root / "operations.jsonl",
        current_tree=root / "current-tree.json",
        cleaned_html=root / "bookmarks.cleaned.html",
        markdown_report=root / "bookmark-report.md",
        html_report=root / "bookmark-report.html",
        decisions=root / "decisions.json",
        link_progress=root / "link-progress.json",
        server_port=root / "review-server.port",
    )


def ensure_workspace(paths: WorkspacePaths) -> None:
    """确保 workspace 目录存在。

    Args:
        paths: workspace 文件路径集合。

    Returns:
        None: 目录创建完成后返回。
    """

    paths.root.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    """写入 JSON 文件。

    Args:
        path: 输出文件路径。
        payload: JSON 友好数据。

    Returns:
        None: 写入完成后返回。
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict[str, Any]:
    """读取 JSON 文件。

    Args:
        path: 输入文件路径。

    Returns:
        dict[str, Any]: JSON 对象。
    """

    return json.loads(path.read_text(encoding="utf-8"))


def append_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    """追加写入 JSONL 记录。

    Args:
        path: JSONL 文件路径。
        records: 要追加的 JSON 友好对象列表。

    Returns:
        None: 写入完成后返回。
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    """读取 JSONL 文件。

    Args:
        path: JSONL 文件路径。

    Returns:
        list[dict[str, Any]]: JSONL 记录；文件不存在时返回空列表。
    """

    if not path.is_file():
        return []
    records: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"JSONL 格式错误: {path}:{line_number}: {exc}") from exc
        if not isinstance(record, dict):
            raise ValueError(f"JSONL 记录必须是对象: {path}:{line_number}")
        records.append(record)
    return records


def create_decision_payload(decisions: dict[str, Any]) -> dict[str, Any]:
    """生成用户选择记录。

    Args:
        decisions: 前端提交的选择数据。

    Returns:
        dict[str, Any]: 带元数据的选择记录。
    """

    return {
        "schemaVersion": 1,
        "savedAt": now_local_iso(),
        "decisions": decisions,
    }
