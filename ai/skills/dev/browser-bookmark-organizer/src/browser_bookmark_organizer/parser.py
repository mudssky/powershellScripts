"""Netscape Bookmark HTML 解析器。"""

from __future__ import annotations

import re
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable

from browser_bookmark_organizer.models import Bookmark, Folder

IGNORED_ATTRS = {"icon"}


def read_bookmark_html(path: Path) -> str:
    """读取浏览器书签 HTML 文件。

    Args:
        path: 本地 HTML 文件路径。

    Returns:
        str: 解码后的 HTML 文本；无法严格解码时用替换字符保留可分析内容。
    """

    data = path.read_bytes()
    detected = detect_charset(data)
    encodings = [detected, "utf-8-sig", "utf-8"] if detected else ["utf-8-sig", "utf-8"]
    for encoding in dict.fromkeys(encodings):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def detect_charset(data: bytes) -> str | None:
    """从 HTML meta 片段里提取 charset。

    Args:
        data: HTML 原始字节。

    Returns:
        str | None: 检测到的编码名称；未检测到时返回 None。
    """

    head = data[:2048].decode("ascii", errors="ignore")
    match = re.search(r"charset=([A-Za-z0-9._-]+)", head, flags=re.IGNORECASE)
    return match.group(1) if match else None


def parse_bookmark_file(path: Path) -> Folder:
    """解析本地 Netscape Bookmark HTML 文件。

    Args:
        path: 本地 HTML 文件路径。

    Returns:
        Folder: 虚拟根节点，包含所有解析出的文件夹与书签。
    """

    return parse_bookmark_html(read_bookmark_html(path))


def parse_bookmark_html(html: str) -> Folder:
    """解析 Netscape Bookmark HTML 文本。

    Args:
        html: HTML 文本。

    Returns:
        Folder: 虚拟根节点，包含所有解析出的文件夹与书签。
    """

    parser = NetscapeBookmarkHTMLParser()
    parser.feed(html)
    parser.close()
    return parser.root


def attrs_to_dict(attrs: Iterable[tuple[str, str | None]]) -> dict[str, str]:
    """转换并过滤 HTML 属性。

    Args:
        attrs: HTMLParser 提供的属性二元组。

    Returns:
        dict[str, str]: 小写属性名到属性值的映射，已过滤大体积 ICON 字段。
    """

    result: dict[str, str] = {}
    for key, value in attrs:
        normalized_key = key.lower()
        if normalized_key in IGNORED_ATTRS:
            continue
        result[normalized_key] = value or ""
    return result


class NetscapeBookmarkHTMLParser(HTMLParser):
    """将 Netscape Bookmark HTML 转换为文件夹树。"""

    def __init__(self) -> None:
        """初始化解析状态。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 初始化方法不返回值。
        """

        super().__init__(convert_charrefs=True)
        self.root = Folder(title="ROOT", path=())
        self._stack: list[Folder] = [self.root]
        self._pending_folder: Folder | None = None
        self._active_tag: str | None = None
        self._active_attrs: dict[str, str] = {}
        self._text_parts: list[str] = []
        self._bookmark_order = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """处理开始标签。

        Args:
            tag: HTML 标签名。
            attrs: 标签属性。

        Returns:
            None: HTMLParser 回调不返回值。
        """

        normalized_tag = tag.lower()
        if normalized_tag == "dl":
            self._start_dl()
            return
        if normalized_tag in {"h3", "a"}:
            self._active_tag = normalized_tag
            self._active_attrs = attrs_to_dict(attrs)
            self._text_parts = []

    def handle_endtag(self, tag: str) -> None:
        """处理结束标签。

        Args:
            tag: HTML 标签名。

        Returns:
            None: HTMLParser 回调不返回值。
        """

        normalized_tag = tag.lower()
        if normalized_tag == "dl":
            self._end_dl()
            return
        if normalized_tag == "h3" and self._active_tag == "h3":
            self._finish_folder()
            return
        if normalized_tag == "a" and self._active_tag == "a":
            self._finish_bookmark()

    def handle_data(self, data: str) -> None:
        """收集当前标题文本。

        Args:
            data: HTMLParser 提供的文本片段。

        Returns:
            None: HTMLParser 回调不返回值。
        """

        if self._active_tag in {"h3", "a"}:
            self._text_parts.append(data)

    def _start_dl(self) -> None:
        """进入文件夹内容列表。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 直接更新内部栈。
        """

        if self._pending_folder is not None:
            self._stack.append(self._pending_folder)
            self._pending_folder = None

    def _end_dl(self) -> None:
        """离开文件夹内容列表。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 直接更新内部栈。
        """

        if len(self._stack) > 1:
            self._stack.pop()

    def _finish_folder(self) -> None:
        """完成一个 H3 文件夹节点。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 新文件夹会追加到当前父文件夹。
        """

        title = normalize_title("".join(self._text_parts))
        parent = self._stack[-1]
        path = (*parent.path, title)
        folder = Folder(title=title, path=path, attrs=self._active_attrs)
        parent.folders.append(folder)
        self._pending_folder = folder
        self._clear_active()

    def _finish_bookmark(self) -> None:
        """完成一个 A 书签节点。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 新书签会追加到当前文件夹。
        """

        title = normalize_title("".join(self._text_parts))
        attrs = self._active_attrs
        url = attrs.get("href", "")
        parent = self._stack[-1]
        self._bookmark_order += 1
        bookmark = Bookmark(
            title=title,
            url=url,
            folder_path=parent.path,
            attrs=attrs,
            order=self._bookmark_order,
        )
        parent.bookmarks.append(bookmark)
        self._clear_active()

    def _clear_active(self) -> None:
        """清理当前正在收集的标签状态。

        Args:
            self: 当前解析器实例。

        Returns:
            None: 直接重置内部状态。
        """

        self._active_tag = None
        self._active_attrs = {}
        self._text_parts = []


def normalize_title(title: str) -> str:
    """规范化标题空白。

    Args:
        title: 原始标题文本。

    Returns:
        str: 合并连续空白后的标题。
    """

    return re.sub(r"\s+", " ", title).strip()
