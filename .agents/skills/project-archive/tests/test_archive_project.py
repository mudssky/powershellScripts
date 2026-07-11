"""project-archive 脚本测试。"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest import mock

SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "archive_project.py"
SPEC = importlib.util.spec_from_file_location("archive_project", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
archive_project = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = archive_project
SPEC.loader.exec_module(archive_project)


def empty_index() -> dict[str, object]:
    """返回测试使用的空索引。

    Returns:
        符合 schema 的空索引对象。
    """

    return {"schemaVersion": 1, "entries": []}


class IndexValidationTests(unittest.TestCase):
    """验证 JSON schema 和路径边界。"""

    def test_rejects_invalid_json(self) -> None:
        """无效 JSON 应返回清晰错误。"""

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.json"
            path.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(archive_project.ArchiveError, "JSON 无效"):
                archive_project.load_index(path)

    def test_rejects_duplicate_sources(self) -> None:
        """不同 ID 不得复用同一源路径。"""

        entry = {
            "id": "batch-1-old",
            "batch": 1,
            "source": "old/file.txt",
            "archive": "archive/old/file.txt",
            "reason": "旧文件",
            "replacement": {"kind": "note", "text": "仅供历史参考"},
        }
        with self.assertRaisesRegex(archive_project.ArchiveError, "重复"):
            archive_project.validate_index({"schemaVersion": 1, "entries": [entry, {**entry, "id": "batch-2-old"}]})

    def test_rejects_non_mirror_archive_path(self) -> None:
        """归档目标必须镜像原路径。"""

        with self.assertRaisesRegex(archive_project.ArchiveError, "必须为 archive/old/file.txt"):
            archive_project.validate_index(
                {
                    "schemaVersion": 1,
                    "entries": [
                        {
                            "id": "batch-1-old",
                            "batch": 1,
                            "source": "old/file.txt",
                            "archive": "archive/file.txt",
                            "reason": "旧文件",
                            "replacement": {"kind": "note", "text": "仅供历史参考"},
                        }
                    ],
                }
            )

    def test_rejects_path_escape(self) -> None:
        """路径不得通过 .. 逃逸仓库。"""

        with self.assertRaisesRegex(archive_project.ArchiveError, "不安全"):
            archive_project.normalize_repo_path("../secret", "source", False)

    def test_atomic_writer_sorts_entries(self) -> None:
        """原子写入应使用稳定排序和末尾换行。"""

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.json"
            entries = []
            for batch, source in ((2, "z.txt"), (1, "a.txt")):
                entries.append(
                    {
                        "id": f"batch-{batch}-{source[0]}",
                        "batch": batch,
                        "source": source,
                        "archive": f"archive/{source}",
                        "reason": "历史文件",
                        "replacement": {"kind": "note", "text": "仅供历史参考"},
                    }
                )
            archive_project.write_index_atomic(path, {"schemaVersion": 1, "entries": entries})
            content = path.read_text(encoding="utf-8")
            self.assertTrue(content.endswith("\n"))
            self.assertEqual(json.loads(content)["entries"][0]["source"], "a.txt")


class RepositoryFlowTests(unittest.TestCase):
    """使用临时 Git 仓库验证计划和执行流程。"""

    def setUp(self) -> None:
        """创建带初始索引和受跟踪源文件的临时仓库。"""

        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        (self.repo / "archive").mkdir()
        archive_project.write_index_atomic(self.repo / "archive/index.json", empty_index())
        (self.repo / "old").mkdir()
        (self.repo / "old/file.txt").write_text("legacy\n", encoding="utf-8")
        subprocess.run(["git", "add", "old/file.txt", "archive/index.json"], cwd=self.repo, check=True)
        self.args = Namespace(
            batch=3,
            reason="旧入口已停止维护",
            replacement_note="仅供历史参考",
            replacement_path=None,
            replacement_text=None,
        )

    def tearDown(self) -> None:
        """清理临时仓库。"""

        self.temporary_directory.cleanup()

    def test_plan_does_not_modify_repository(self) -> None:
        """plan 只返回结构化结果，不移动文件或改写索引。"""

        before = (self.repo / "archive/index.json").read_text(encoding="utf-8")
        plan = archive_project.build_plan(self.repo, empty_index(), ["old/file.txt"], self.args)
        self.assertEqual(plan["items"][0]["entry"]["archive"], "archive/old/file.txt")
        self.assertTrue((self.repo / "old/file.txt").exists())
        self.assertEqual((self.repo / "archive/index.json").read_text(encoding="utf-8"), before)

    def test_execute_moves_file_and_updates_index(self) -> None:
        """显式执行应完成 git mv 并同步索引。"""

        index_path = self.repo / "archive/index.json"
        plan = archive_project.build_plan(self.repo, empty_index(), ["old/file.txt"], self.args)
        updated = archive_project.execute_archive(self.repo, index_path, empty_index(), plan)
        self.assertFalse((self.repo / "old/file.txt").exists())
        self.assertTrue((self.repo / "archive/old/file.txt").exists())
        self.assertEqual(updated["entries"][0]["source"], "old/file.txt")
        self.assertEqual(archive_project.check_repository(self.repo, updated), [])

    def test_rejects_existing_target(self) -> None:
        """目标已存在时必须在执行前失败。"""

        (self.repo / "archive/old").mkdir()
        (self.repo / "archive/old/file.txt").write_text("conflict\n", encoding="utf-8")
        with self.assertRaisesRegex(archive_project.ArchiveError, "目标已存在"):
            archive_project.build_plan(self.repo, empty_index(), ["old/file.txt"], self.args)

    def test_rolls_back_when_index_write_fails(self) -> None:
        """索引写入失败时应反向移动已完成对象。"""

        index_path = self.repo / "archive/index.json"
        plan = archive_project.build_plan(self.repo, empty_index(), ["old/file.txt"], self.args)
        with mock.patch.object(archive_project, "write_index_atomic", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(archive_project.ArchiveError, "已回滚"):
                archive_project.execute_archive(self.repo, index_path, empty_index(), plan)
        self.assertTrue((self.repo / "old/file.txt").exists())
        self.assertFalse((self.repo / "archive/old/file.txt").exists())

    def test_archive_cli_requires_execute(self) -> None:
        """archive 子命令缺少 --execute 时不得修改仓库。"""

        exit_code = archive_project.main(
            [
                "--repo-root",
                str(self.repo),
                "archive",
                "old/file.txt",
                "--batch",
                "3",
                "--reason",
                "旧入口已停止维护",
                "--replacement-note",
                "仅供历史参考",
            ]
        )
        self.assertEqual(exit_code, 2)
        self.assertTrue((self.repo / "old/file.txt").exists())

    def test_check_reports_untracked_archive_target(self) -> None:
        """存在但未被 Git 跟踪的归档目标必须被报告。"""

        (self.repo / "old/file.txt").unlink()
        target = self.repo / "archive/old/file.txt"
        target.parent.mkdir(parents=True)
        target.write_text("legacy\n", encoding="utf-8")
        index = archive_project.validate_index(
            {
                "schemaVersion": 1,
                "entries": [
                    {
                        "id": "batch-3-old-file-txt",
                        "batch": 3,
                        "source": "old/file.txt",
                        "archive": "archive/old/file.txt",
                        "reason": "旧文件",
                        "replacement": {"kind": "note", "text": "仅供历史参考"},
                    }
                ],
            }
        )
        errors = archive_project.check_repository(self.repo, index)
        self.assertIn("归档路径没有 Git 跟踪文件: archive/old/file.txt", errors)
