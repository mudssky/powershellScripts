from pathlib import Path

from browser_bookmark_organizer.analysis import flatten_bookmarks, flatten_folders
from browser_bookmark_organizer.parser import parse_bookmark_file

FIXTURE = Path(__file__).parent / "fixtures" / "sample_bookmarks.html"


def test_parse_netscape_bookmark_html_tree() -> None:
    """验证 Netscape Bookmark HTML 能解析出层级树。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    root = parse_bookmark_file(FIXTURE)

    folders = flatten_folders(root)
    bookmarks = flatten_bookmarks(root)

    assert [folder.display_path for folder in folders] == [
        "/Bookmarks Bar",
        "/Bookmarks Bar/Dev",
        "/Bookmarks Bar/Empty Folder",
    ]
    assert len(bookmarks) == 5
    assert bookmarks[0].title == "Example Docs"
    assert bookmarks[0].attrs["href"] == "https://example.com/docs/"
    assert "icon" not in bookmarks[0].attrs
    assert bookmarks[-1].folder_display_path == "/Bookmarks Bar/Dev"
