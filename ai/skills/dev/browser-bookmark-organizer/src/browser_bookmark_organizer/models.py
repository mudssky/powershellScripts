"""书签树与报告领域模型。"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class Bookmark:
    """浏览器书签条目。

    Args:
        title: 书签标题。
        url: 原始 URL。
        folder_path: 书签所在文件夹路径，不包含虚拟根节点。
        attrs: 书签导出属性，已过滤大体积 ICON 字段。
        order: 书签在解析流中的顺序。

    Returns:
        Bookmark: 结构化书签条目。
    """

    title: str
    url: str
    folder_path: tuple[str, ...]
    attrs: dict[str, str] = field(default_factory=dict)
    order: int = 0

    @property
    def folder_display_path(self) -> str:
        """返回用于报告展示的文件夹路径。

        Args:
            self: 当前书签。

        Returns:
            str: 以 `/` 拼接的路径；根层级显示为 `/`。
        """

        return "/" if not self.folder_path else "/" + "/".join(self.folder_path)


@dataclass(slots=True)
class Folder:
    """浏览器书签文件夹。

    Args:
        title: 文件夹标题。
        path: 文件夹路径，不包含虚拟根节点。
        attrs: 文件夹导出属性。
        folders: 子文件夹列表。
        bookmarks: 直属书签列表。

    Returns:
        Folder: 结构化文件夹节点。
    """

    title: str
    path: tuple[str, ...]
    attrs: dict[str, str] = field(default_factory=dict)
    folders: list[Folder] = field(default_factory=list)
    bookmarks: list[Bookmark] = field(default_factory=list)

    @property
    def display_path(self) -> str:
        """返回用于报告展示的文件夹路径。

        Args:
            self: 当前文件夹。

        Returns:
            str: 以 `/` 拼接的路径；根层级显示为 `/`。
        """

        return "/" if not self.path else "/" + "/".join(self.path)


@dataclass(frozen=True, slots=True)
class DuplicateGroup:
    """规范化 URL 后的重复书签组。

    Args:
        normalized_url: 规范化后的 URL。
        bookmarks: 命中同一规范化 URL 的书签。

    Returns:
        DuplicateGroup: 重复项分组。
    """

    normalized_url: str
    bookmarks: tuple[Bookmark, ...]


@dataclass(frozen=True, slots=True)
class SuspiciousTitle:
    """标题异常候选。

    Args:
        bookmark: 命中的书签。
        reason: 异常原因。

    Returns:
        SuspiciousTitle: 标题异常记录。
    """

    bookmark: Bookmark
    reason: str


@dataclass(frozen=True, slots=True)
class BookmarkAnalysis:
    """书签离线分析结果。

    Args:
        input_path: 被分析的输入路径。
        root: 解析后的虚拟根节点。
        folders: 展平后的文件夹列表，不包含虚拟根节点。
        bookmarks: 展平后的书签列表。
        scheme_counts: URL scheme 计数。
        domain_counts: domain 计数。
        duplicate_groups: 规范化 URL 重复项。
        empty_folders: 无书签后代的文件夹。
        dedup_at_risk_folders: 去重后可能变空的文件夹（仅含重复书签的叶目录）。
        suspicious_titles: 空标题或疑似乱码标题。
        max_depth: 最大目录深度。

    Returns:
        BookmarkAnalysis: 离线分析聚合结果。
    """

    input_path: str
    root: Folder
    folders: tuple[Folder, ...]
    bookmarks: tuple[Bookmark, ...]
    scheme_counts: dict[str, int]
    domain_counts: dict[str, int]
    duplicate_groups: tuple[DuplicateGroup, ...]
    empty_folders: tuple[Folder, ...]
    suspicious_titles: tuple[SuspiciousTitle, ...]
    max_depth: int
    dedup_at_risk_folders: tuple[Folder, ...] = ()
