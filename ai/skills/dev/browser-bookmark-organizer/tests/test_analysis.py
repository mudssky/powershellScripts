from pathlib import Path

from browser_bookmark_organizer.analysis import analyze_bookmarks, normalize_url
from browser_bookmark_organizer.parser import parse_bookmark_file

FIXTURE = Path(__file__).parent / "fixtures" / "sample_bookmarks.html"


def test_analyze_bookmarks_finds_duplicates_empty_folders_and_titles() -> None:
    """验证离线分析能发现重复项、空目录和疑似乱码标题。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    analysis = analyze_bookmarks(parse_bookmark_file(FIXTURE), FIXTURE)

    assert len(analysis.folders) == 3
    assert len(analysis.bookmarks) == 5
    assert analysis.max_depth == 2
    assert analysis.scheme_counts["https"] == 4
    assert analysis.scheme_counts["file"] == 1
    assert analysis.domain_counts["example.com"] == 2
    assert [group.normalized_url for group in analysis.duplicate_groups] == [
        "https://example.com/docs"
    ]
    assert [folder.display_path for folder in analysis.empty_folders] == [
        "/Bookmarks Bar/Empty Folder"
    ]
    assert analysis.suspicious_titles[0].bookmark.url == "https://bad-title.example"


def test_normalize_url_removes_fragment_case_and_default_port() -> None:
    """验证 URL 规范化规则。

    Args:
        None.

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    assert normalize_url("HTTPS://Example.COM:443/docs/#intro") == "https://example.com/docs"
