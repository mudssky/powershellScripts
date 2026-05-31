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
