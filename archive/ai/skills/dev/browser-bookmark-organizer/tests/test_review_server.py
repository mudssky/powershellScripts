import json
from pathlib import Path

from fastapi.testclient import TestClient

from browser_bookmark_organizer.review_server import create_app


def test_review_server_reads_analysis_and_saves_decisions(tmp_path: Path) -> None:
    """验证本地 review 服务能读取分析数据并保存用户选择。

    Args:
        tmp_path: pytest 提供的临时目录。

    Returns:
        None: 断言失败时由 pytest 报错。
    """

    analysis_payload = {
        "summary": {"bookmarkCount": 2},
        "suspiciousTitles": [],
        "emptyFolders": [],
        "duplicates": [],
        "linkChecks": {"enabled": False},
    }
    (tmp_path / "analysis.json").write_text(
        json.dumps(analysis_payload, ensure_ascii=False),
        encoding="utf-8",
    )

    client = TestClient(create_app(tmp_path))

    page_response = client.get("/")
    analysis_response = client.get("/api/analysis")
    save_response = client.post(
        "/api/decisions",
        json={"decisions": {"selected": {"title:1": True}, "note": "先保留死链"}},
    )
    export_response = client.post("/api/export")
    decisions_response = client.get("/api/decisions")

    assert page_response.status_code == 200
    assert "浏览器书签审核工作台" in page_response.text
    assert 'data-view="overview"' in page_response.text
    assert analysis_response.json()["summary"]["bookmarkCount"] == 2
    assert save_response.status_code == 200
    assert export_response.status_code == 404
    decisions_payload = decisions_response.json()
    assert decisions_payload["schemaVersion"] == 1
    assert decisions_payload["decisions"]["selected"]["title:1"] is True
    assert (tmp_path / "decisions.json").is_file()
