"""书签离线分析逻辑。"""

from __future__ import annotations

from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from browser_bookmark_organizer.models import (
    Bookmark,
    BookmarkAnalysis,
    DuplicateGroup,
    Folder,
    SuspiciousTitle,
)

MOJIBAKE_MARKERS = (
    "\ufffd",
    "Ã",
    "Â",
    "â€",
    "â€™",
    "â€œ",
    "â€“",
    "ä¸",
    "æ–",
    "çš",
    "å",
    "ã€",
    "ãƒ",
    "ðŸ",
)


def analyze_bookmarks(root: Folder, input_path: Path | str) -> BookmarkAnalysis:
    """计算书签树的离线分析结果。

    Args:
        root: 解析后的虚拟根节点。
        input_path: 输入文件路径，用于报告展示。

    Returns:
        BookmarkAnalysis: 统计、重复、空目录和标题异常的聚合结果。
    """

    folders = tuple(flatten_folders(root))
    bookmarks = tuple(flatten_bookmarks(root))
    duplicate_groups = find_duplicate_groups(bookmarks)
    empty_folders = tuple(folder for folder in folders if count_descendant_bookmarks(folder) == 0)
    dedup_at_risk_folders = tuple(find_dedup_at_risk_folders(folders, duplicate_groups))
    suspicious_titles = tuple(find_suspicious_titles(bookmarks))
    return BookmarkAnalysis(
        input_path=str(input_path),
        root=root,
        folders=folders,
        bookmarks=bookmarks,
        scheme_counts=count_schemes(bookmarks),
        domain_counts=count_domains(bookmarks),
        duplicate_groups=duplicate_groups,
        empty_folders=empty_folders,
        dedup_at_risk_folders=dedup_at_risk_folders,
        suspicious_titles=suspicious_titles,
        max_depth=max_depth(root),
    )


def flatten_folders(root: Folder) -> list[Folder]:
    """按深度优先顺序展开文件夹。

    Args:
        root: 起始文件夹；通常是虚拟根节点。

    Returns:
        list[Folder]: 不包含虚拟根节点的文件夹列表。
    """

    result: list[Folder] = []
    for folder in root.folders:
        result.append(folder)
        result.extend(flatten_folders(folder))
    return result


def flatten_bookmarks(root: Folder) -> list[Bookmark]:
    """按深度优先顺序展开书签。

    Args:
        root: 起始文件夹；通常是虚拟根节点。

    Returns:
        list[Bookmark]: 所有书签条目。
    """

    result = list(root.bookmarks)
    for folder in root.folders:
        result.extend(flatten_bookmarks(folder))
    return result


def count_descendant_bookmarks(folder: Folder) -> int:
    """统计文件夹自身和后代中的书签数量。

    Args:
        folder: 要统计的文件夹。

    Returns:
        int: 该文件夹下所有书签数量。
    """

    return len(folder.bookmarks) + sum(
        count_descendant_bookmarks(child) for child in folder.folders
    )


def count_schemes(bookmarks: tuple[Bookmark, ...] | list[Bookmark]) -> dict[str, int]:
    """统计 URL scheme。

    Args:
        bookmarks: 书签列表。

    Returns:
        dict[str, int]: scheme 到数量的映射；缺失 scheme 用 `(missing)` 表示。
    """

    counter: Counter[str] = Counter()
    for bookmark in bookmarks:
        scheme = urlsplit(bookmark.url).scheme.lower() or "(missing)"
        counter[scheme] += 1
    return dict(counter.most_common())


def count_domains(bookmarks: tuple[Bookmark, ...] | list[Bookmark]) -> dict[str, int]:
    """统计 URL domain。

    Args:
        bookmarks: 书签列表。

    Returns:
        dict[str, int]: domain 到数量的映射；缺失 domain 用 `(none)` 表示。
    """

    counter: Counter[str] = Counter()
    for bookmark in bookmarks:
        parts = urlsplit(bookmark.url)
        domain = (parts.hostname or "(none)").lower()
        counter[domain] += 1
    return dict(counter.most_common())


def find_duplicate_groups(
    bookmarks: tuple[Bookmark, ...] | list[Bookmark],
) -> tuple[DuplicateGroup, ...]:
    """查找规范化 URL 后的重复书签。

    Args:
        bookmarks: 书签列表。

    Returns:
        tuple[DuplicateGroup, ...]: 按重复数量降序排列的重复组。
    """

    groups: dict[str, list[Bookmark]] = defaultdict(list)
    for bookmark in bookmarks:
        normalized = normalize_url(bookmark.url)
        if normalized:
            groups[normalized].append(bookmark)

    duplicates = [
        DuplicateGroup(normalized_url=url, bookmarks=tuple(items))
        for url, items in groups.items()
        if len(items) > 1
    ]
    return tuple(
        sorted(duplicates, key=lambda group: (-len(group.bookmarks), group.normalized_url))
    )


def normalize_url(url: str) -> str:
    """规范化 URL 以便发现明显重复项。

    Args:
        url: 原始 URL。

    Returns:
        str: 去掉 fragment、统一大小写和默认端口后的 URL。
    """

    stripped = url.strip()
    if not stripped:
        return ""
    parts = urlsplit(stripped)
    scheme = parts.scheme.lower()
    hostname = (parts.hostname or "").lower()
    try:
        port = parts.port
    except ValueError:
        port = None

    if hostname:
        default_port = (scheme == "http" and port == 80) or (scheme == "https" and port == 443)
        netloc = hostname if port is None or default_port else f"{hostname}:{port}"
    else:
        netloc = parts.netloc.lower()

    path = parts.path
    if scheme in {"http", "https"} and hostname:
        path = path.rstrip("/") or "/"

    return urlunsplit((scheme, netloc, path, parts.query, ""))


def find_suspicious_titles(
    bookmarks: tuple[Bookmark, ...] | list[Bookmark],
) -> list[SuspiciousTitle]:
    """查找空标题或疑似乱码标题。

    Args:
        bookmarks: 书签列表。

    Returns:
        list[SuspiciousTitle]: 标题异常候选列表。
    """

    result: list[SuspiciousTitle] = []
    for bookmark in bookmarks:
        reason = suspicious_title_reason(bookmark.title)
        if reason:
            result.append(SuspiciousTitle(bookmark=bookmark, reason=reason))
    return result


def suspicious_title_reason(title: str) -> str | None:
    """判断标题是否可疑。

    Args:
        title: 书签标题。

    Returns:
        str | None: 异常原因；正常标题返回 None。
    """

    if not title.strip():
        return "empty_title"
    if "\ufffd" in title:
        return "replacement_character"
    hits = [marker for marker in MOJIBAKE_MARKERS if marker in title]
    # 乱码检测只做候选标记；要求至少两个常见 marker，降低法语/德语标题误判概率。
    if len(hits) >= 2:
        return "mojibake_markers:" + ",".join(hits[:4])
    return None


def find_dedup_at_risk_folders(
    folders: tuple[Folder, ...],
    duplicate_groups: tuple[DuplicateGroup, ...],
) -> list[Folder]:
    """查找去重后可能变空的文件夹。

    模拟每组重复书签只保留第一个，计算哪些文件夹的后代书签数会降为零。

    Args:
        folders: 所有文件夹。
        duplicate_groups: 重复书签分组。

    Returns:
        list[Folder]: 去重后会变空的文件夹列表。
    """

    if not duplicate_groups:
        return []
    # 收集需要移除的书签 id（每组保留第一个）
    ids_to_remove: set[tuple[str, str]] = set()
    for group in duplicate_groups:
        for bookmark in group.bookmarks[1:]:
            ids_to_remove.add((bookmark.url, bookmark.folder_path, bookmark.order))
    if not ids_to_remove:
        return []
    # 重新计算每个文件夹的去重后后代书签数
    at_risk: list[Folder] = []
    for folder in folders:
        original = count_descendant_bookmarks(folder)
        if original == 0:
            continue
        remaining = count_descendant_bookmarks_excluding(folder, ids_to_remove)
        if remaining == 0:
            at_risk.append(folder)
    return at_risk


def count_descendant_bookmarks_excluding(
    folder: Folder,
    excluded: set[tuple[str, str, int]],
) -> int:
    """统计文件夹后代中排除指定书签后的数量。

    Args:
        folder: 要统计的文件夹。
        excluded: 需要排除的书签标识集合 (url, folder_path, order)。

    Returns:
        int: 排除后的后代书签数量。
    """

    count = sum(1 for bm in folder.bookmarks if (bm.url, bm.folder_path, bm.order) not in excluded)
    return count + sum(
        count_descendant_bookmarks_excluding(child, excluded) for child in folder.folders
    )


def max_depth(root: Folder) -> int:
    """计算最大目录深度。

    Args:
        root: 起始文件夹；通常是虚拟根节点。

    Returns:
        int: 最大目录层级，根层级为 0。
    """

    folder_depths = [len(folder.path) for folder in flatten_folders(root)]
    bookmark_depths = [len(bookmark.folder_path) for bookmark in flatten_bookmarks(root)]
    return max([0, *folder_depths, *bookmark_depths])
