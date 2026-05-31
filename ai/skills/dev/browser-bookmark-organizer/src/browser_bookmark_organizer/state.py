"""书签 snapshot、operation replay 与导出。"""

from __future__ import annotations

from copy import deepcopy
from html import escape
from typing import Any

from browser_bookmark_organizer.analysis import flatten_bookmarks, flatten_folders
from browser_bookmark_organizer.clock import now_local, now_local_iso
from browser_bookmark_organizer.models import Folder

SUPPORTED_OPS = {
    "create_folder",
    "rename_folder",
    "move_folder",
    "delete_empty_folder",
    "move_bookmark",
    "rename_bookmark",
    "update_url",
    "mark_bookmark",
    "archive_bookmark",
}


def build_snapshot(root: Folder, input_path: str) -> dict[str, Any]:
    """从解析树生成只读 snapshot。

    Args:
        root: 解析后的虚拟根节点。
        input_path: 原始 HTML 文件路径。

    Returns:
        dict[str, Any]: JSON 友好的原始快照。
    """

    folders = sorted(flatten_folders(root), key=lambda folder: (len(folder.path), folder.path))
    bookmarks = sorted(flatten_bookmarks(root), key=lambda bookmark: bookmark.order)
    return {
        "schemaVersion": 1,
        "input": input_path,
        "createdAt": now_local_iso(),
        "folders": [
            {
                "path": list(folder.path),
                "title": folder.title,
                "attrs": folder.attrs,
            }
            for folder in folders
        ],
        "bookmarks": [
            {
                "id": bookmark_id(bookmark.order),
                "order": bookmark.order,
                "title": bookmark.title,
                "url": bookmark.url,
                "folderPath": list(bookmark.folder_path),
                "attrs": bookmark.attrs,
                "marks": [],
                "archived": False,
                "deleted": False,
            }
            for bookmark in bookmarks
        ],
    }


def bookmark_id(order: int) -> str:
    """生成稳定书签 ID。

    Args:
        order: 书签解析顺序。

    Returns:
        str: 稳定 ID，例如 `b_000001`。
    """

    return f"b_{order:06d}"


def replay_operations(
    snapshot: dict[str, Any],
    operations: list[dict[str, Any]],
) -> dict[str, Any]:
    """基于 snapshot 和 operations 派生当前状态。

    Args:
        snapshot: 原始快照。
        operations: 已批准操作列表。

    Returns:
        dict[str, Any]: 当前状态。
    """

    state = {
        "schemaVersion": 1,
        "sourceInput": snapshot.get("input"),
        "folders": [deepcopy(folder) for folder in snapshot.get("folders", [])],
        "bookmarks": [deepcopy(bookmark) for bookmark in snapshot.get("bookmarks", [])],
        "appliedOperations": [],
    }
    ensure_folder(state, [])
    for operation in operations:
        apply_operation(state, operation)
        state["appliedOperations"].append(operation)
    return state


def apply_operation(state: dict[str, Any], operation: dict[str, Any]) -> None:
    """应用单条 operation 到当前状态。

    Args:
        state: 当前状态对象，会被原地修改。
        operation: 操作对象。

    Returns:
        None: 应用完成后返回。
    """

    op = operation.get("op")
    if op not in SUPPORTED_OPS:
        raise ValueError(f"不支持的 operation: {op}")
    if op == "create_folder":
        ensure_folder(state, path_tuple(operation["path"]))
    elif op == "rename_folder":
        rename_folder(state, path_tuple(operation["fromPath"]), path_tuple(operation["toPath"]))
    elif op == "move_folder":
        move_folder(state, path_tuple(operation["fromPath"]), path_tuple(operation["toPath"]))
    elif op == "delete_empty_folder":
        delete_empty_folder(state, path_tuple(operation["path"]))
    elif op == "move_bookmark":
        move_bookmark(state, str(operation["bookmarkId"]), path_tuple(operation["toPath"]))
    elif op == "rename_bookmark":
        bookmark = find_bookmark(state, str(operation["bookmarkId"]))
        bookmark["title"] = str(operation["title"])
    elif op == "update_url":
        bookmark = find_bookmark(state, str(operation["bookmarkId"]))
        bookmark["url"] = str(operation["url"])
    elif op == "mark_bookmark":
        mark_bookmark(state, str(operation["bookmarkId"]), str(operation["mark"]))
    elif op == "archive_bookmark":
        to_path = path_tuple(operation.get("toPath", ["_Archive"]))
        move_bookmark(state, str(operation["bookmarkId"]), to_path)
        find_bookmark(state, str(operation["bookmarkId"]))["archived"] = True


def ensure_folder(state: dict[str, Any], path: tuple[str, ...]) -> None:
    """确保目录存在。

    Args:
        state: 当前状态。
        path: 目录路径。

    Returns:
        None: 目录存在后返回。
    """

    folders = state["folders"]
    existing = {tuple(folder["path"]) for folder in folders}
    for index in range(1, len(path) + 1):
        current = path[:index]
        if current not in existing:
            folders.append({"path": list(current), "title": current[-1], "attrs": {}})
            existing.add(current)


def rename_folder(
    state: dict[str, Any], from_path: tuple[str, ...], to_path: tuple[str, ...]
) -> None:
    """重命名目录及其后代路径。

    Args:
        state: 当前状态。
        from_path: 原目录路径。
        to_path: 新目录路径。

    Returns:
        None: 重命名完成后返回。
    """

    if not from_path:
        raise ValueError("不能重命名根目录")
    move_folder(state, from_path, to_path)


def move_folder(
    state: dict[str, Any], from_path: tuple[str, ...], to_path: tuple[str, ...]
) -> None:
    """移动目录及其后代书签。

    Args:
        state: 当前状态。
        from_path: 原目录路径。
        to_path: 新目录路径。

    Returns:
        None: 移动完成后返回。
    """

    if not from_path:
        raise ValueError("不能移动根目录")
    if to_path[: len(from_path)] == from_path:
        raise ValueError("不能把目录移动到自身后代下")
    ensure_folder(state, to_path[:-1])
    matched = False
    for folder in state["folders"]:
        path = tuple(folder["path"])
        if path == from_path or path[: len(from_path)] == from_path:
            suffix = path[len(from_path) :]
            new_path = (*to_path, *suffix)
            folder["path"] = list(new_path)
            folder["title"] = new_path[-1] if new_path else "ROOT"
            matched = True
    if not matched:
        raise ValueError(f"目录不存在: {format_path(from_path)}")
    for bookmark in state["bookmarks"]:
        folder_path = tuple(bookmark["folderPath"])
        if folder_path == from_path or folder_path[: len(from_path)] == from_path:
            bookmark["folderPath"] = list((*to_path, *folder_path[len(from_path) :]))


def delete_empty_folder(state: dict[str, Any], path: tuple[str, ...]) -> None:
    """删除空目录。

    Args:
        state: 当前状态。
        path: 要删除的目录路径。

    Returns:
        None: 删除完成后返回。
    """

    if any(
        tuple(folder["path"])[: len(path)] == path and tuple(folder["path"]) != path
        for folder in state["folders"]
    ):
        raise ValueError(f"目录存在子目录，不能删除: {format_path(path)}")
    if any(
        tuple(bookmark["folderPath"]) == path and not bookmark.get("deleted")
        for bookmark in state["bookmarks"]
    ):
        raise ValueError(f"目录存在书签，不能删除: {format_path(path)}")
    before = len(state["folders"])
    state["folders"] = [folder for folder in state["folders"] if tuple(folder["path"]) != path]
    if len(state["folders"]) == before:
        raise ValueError(f"目录不存在: {format_path(path)}")


def move_bookmark(state: dict[str, Any], bookmark_id_value: str, to_path: tuple[str, ...]) -> None:
    """移动书签到目标目录。

    Args:
        state: 当前状态。
        bookmark_id_value: 书签 ID。
        to_path: 目标目录路径。

    Returns:
        None: 移动完成后返回。
    """

    ensure_folder(state, to_path)
    bookmark = find_bookmark(state, bookmark_id_value)
    bookmark["folderPath"] = list(to_path)


def mark_bookmark(state: dict[str, Any], bookmark_id_value: str, mark: str) -> None:
    """给书签添加标记。

    Args:
        state: 当前状态。
        bookmark_id_value: 书签 ID。
        mark: 标记名称。

    Returns:
        None: 标记完成后返回。
    """

    bookmark = find_bookmark(state, bookmark_id_value)
    marks = bookmark.setdefault("marks", [])
    if mark not in marks:
        marks.append(mark)


def find_bookmark(state: dict[str, Any], bookmark_id_value: str) -> dict[str, Any]:
    """查找书签。

    Args:
        state: 当前状态。
        bookmark_id_value: 书签 ID。

    Returns:
        dict[str, Any]: 书签对象。
    """

    for bookmark in state["bookmarks"]:
        if bookmark["id"] == bookmark_id_value:
            return bookmark
    raise ValueError(f"书签不存在: {bookmark_id_value}")


def build_tree_payload(state: dict[str, Any]) -> dict[str, Any]:
    """生成当前目录树摘要。

    Args:
        state: 当前状态。

    Returns:
        dict[str, Any]: 目录树摘要，包含扁平列表和嵌套树结构。
    """

    bookmark_counts: dict[tuple[str, ...], int] = {}
    folder_bookmarks: dict[tuple[str, ...], list[dict[str, Any]]] = {}
    for bookmark in state["bookmarks"]:
        if bookmark.get("deleted"):
            continue
        path = tuple(bookmark["folderPath"])
        bookmark_counts[path] = bookmark_counts.get(path, 0) + 1
        folder_bookmarks.setdefault(path, []).append(bookmark)

    folders = sorted(
        [folder for folder in state["folders"] if folder["path"]],
        key=lambda folder: (len(folder["path"]), folder["path"]),
    )
    return {
        "folderCount": len(folders),
        "bookmarkCount": sum(bookmark_counts.values()),
        "folders": [
            {
                "path": folder["path"],
                "displayPath": "/" + "/".join(folder["path"]),
                "depth": len(folder["path"]),
                "directBookmarkCount": bookmark_counts.get(tuple(folder["path"]), 0),
            }
            for folder in folders
        ],
        "tree": _build_nested_tree(state, folder_bookmarks),
    }


def _build_nested_tree(
    state: dict[str, Any],
    folder_bookmarks: dict[tuple[str, ...], list[dict[str, Any]]],
) -> dict[str, Any]:
    """递归构建嵌套目录树。

    Args:
        state: 当前状态。
        folder_bookmarks: 路径到直属书签列表的映射。

    Returns:
        dict[str, Any]: 嵌套树根节点。
    """

    def build_node(path: tuple[str, ...]) -> dict[str, Any]:
        """构建单个目录节点。

        Args:
            path: 目录路径。

        Returns:
            dict[str, Any]: 包含 children、bookmarks 的目录节点。
        """
        direct_bookmarks = [
            {
                "id": bm["id"],
                "title": bm["title"],
                "url": bm["url"],
            }
            for bm in folder_bookmarks.get(path, [])
        ]
        child_names = child_folder_names(state, path)
        children = [build_node((*path, name)) for name in child_names]
        return {
            "name": path[-1] if path else "ROOT",
            "path": list(path),
            "bookmarkCount": len(direct_bookmarks),
            "bookmarks": direct_bookmarks,
            "children": children,
        }

    root_children = [build_node((name,)) for name in child_folder_names(state, ())]
    return {"children": root_children}


def render_tree_markdown(tree_payload: dict[str, Any]) -> str:
    """渲染目录树 Markdown。

    Args:
        tree_payload: `build_tree_payload` 的返回值。

    Returns:
        str: Markdown 文本。
    """

    lines = [
        "# 当前书签目录树",
        "",
        f"- 文件夹：{tree_payload['folderCount']}",
        f"- 书签：{tree_payload['bookmarkCount']}",
        "",
    ]
    folder_by_path = {tuple(folder["path"]): folder for folder in tree_payload["folders"]}
    children: dict[tuple[str, ...], list[tuple[str, ...]]] = {}
    for path in folder_by_path:
        parent = path[:-1]
        children.setdefault(parent, []).append(path)
    append_tree_markdown(lines, folder_by_path, children, ())
    return "\n".join(lines).rstrip() + "\n"


def append_tree_markdown(
    lines: list[str],
    folder_by_path: dict[tuple[str, ...], dict[str, Any]],
    children: dict[tuple[str, ...], list[tuple[str, ...]]],
    parent: tuple[str, ...],
    depth: int = 0,
) -> None:
    """递归追加目录树 Markdown。

    Args:
        lines: Markdown 行列表。
        folder_by_path: 路径到目录摘要的映射。
        children: 父路径到子路径列表的映射。
        parent: 当前父路径。
        depth: 当前缩进深度。

    Returns:
        None: 直接追加到 lines。
    """

    for path in sorted(children.get(parent, [])):
        folder = folder_by_path[path]
        indent = "  " * depth
        title = path[-1]
        lines.append(f"{indent}- {title} ({folder['directBookmarkCount']})")
        append_tree_markdown(lines, folder_by_path, children, path, depth + 1)


def export_netscape_html(state: dict[str, Any]) -> str:
    """导出 Netscape Bookmark HTML。

    Args:
        state: 当前状态。

    Returns:
        str: 可导入浏览器的新书签 HTML。
    """

    lines = [
        "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
        '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
        "<TITLE>Bookmarks</TITLE>",
        "<H1>Bookmarks</H1>",
        "<DL><p>",
    ]
    append_folder_html(lines, state, ())
    lines.append("</DL><p>")
    return "\n".join(lines) + "\n"


def append_folder_html(
    lines: list[str], state: dict[str, Any], path: tuple[str, ...], depth: int = 1
) -> None:
    """递归追加目录 HTML。

    Args:
        lines: HTML 行列表。
        state: 当前状态。
        path: 当前目录路径。
        depth: 缩进深度。

    Returns:
        None: 直接追加到 lines。
    """

    indent = "    " * depth
    for bookmark in sorted_bookmarks_in_folder(state, path):
        attrs = bookmark_attrs_to_html(bookmark)
        lines.append(f"{indent}<DT><A {attrs}>{escape(str(bookmark['title']))}</A>")
    for child in child_folder_names(state, path):
        child_path = (*path, child)
        lines.append(f"{indent}<DT><H3>{escape(child)}</H3>")
        lines.append(f"{indent}<DL><p>")
        append_folder_html(lines, state, child_path, depth + 1)
        lines.append(f"{indent}</DL><p>")


def sorted_bookmarks_in_folder(
    state: dict[str, Any], path: tuple[str, ...]
) -> list[dict[str, Any]]:
    """返回目录下的直属书签。

    Args:
        state: 当前状态。
        path: 目录路径。

    Returns:
        list[dict[str, Any]]: 按原始顺序排列的书签。
    """

    return sorted(
        [
            bookmark
            for bookmark in state["bookmarks"]
            if tuple(bookmark["folderPath"]) == path and not bookmark.get("deleted")
        ],
        key=lambda bookmark: bookmark.get("order", 0),
    )


def child_folder_names(state: dict[str, Any], path: tuple[str, ...]) -> list[str]:
    """获取直属子目录名。

    Args:
        state: 当前状态。
        path: 父目录路径。

    Returns:
        list[str]: 子目录名列表。
    """

    names = {
        tuple(folder["path"])[len(path)]
        for folder in state["folders"]
        if len(folder["path"]) == len(path) + 1 and tuple(folder["path"])[: len(path)] == path
    }
    return sorted(names)


def bookmark_attrs_to_html(bookmark: dict[str, Any]) -> str:
    """渲染书签 HTML 属性。

    Args:
        bookmark: 当前状态中的书签对象。

    Returns:
        str: HTML 属性文本。
    """

    attrs = dict(bookmark.get("attrs", {}))
    attrs["href"] = bookmark["url"]
    return " ".join(
        f'{key.upper()}="{escape(str(value), quote=True)}"' for key, value in attrs.items() if value
    )


def normalize_operation(raw: dict[str, Any], index: int) -> dict[str, Any]:
    """规范化 operation 元数据。

    Args:
        raw: 输入 operation。
        index: 本批次内序号。

    Returns:
        dict[str, Any]: 带默认元数据的 operation。
    """

    operation = dict(raw)
    operation.setdefault("opId", f"op_{now_local().strftime('%Y%m%d%H%M%S')}_{index:04d}")
    operation.setdefault("phase", "bookmark_assignment")
    operation.setdefault("createdAt", now_local_iso())
    operation.setdefault("approved", True)
    return operation


def approved_operations(operations: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """过滤已批准 operation。

    Args:
        operations: operation 列表。

    Returns:
        list[dict[str, Any]]: 已批准 operation。
    """

    return [operation for operation in operations if operation.get("approved", True)]


def path_tuple(value: Any) -> tuple[str, ...]:
    """把 JSON 路径转换为 tuple。

    Args:
        value: JSON 中的路径值。

    Returns:
        tuple[str, ...]: 目录路径。
    """

    if value is None:
        return ()
    if not isinstance(value, list) or not all(isinstance(part, str) for part in value):
        raise ValueError(f"路径必须是字符串数组: {value}")
    return tuple(value)


def format_path(path: tuple[str, ...]) -> str:
    """格式化路径。

    Args:
        path: 目录路径。

    Returns:
        str: 展示路径。
    """

    return "/" if not path else "/" + "/".join(path)
