#!/usr/bin/env python3
"""安全规划、执行并校验 Git 仓库冷归档。"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA_VERSION = 1
DEFAULT_INDEX_PATH = PurePosixPath("archive/index.json")


class ArchiveError(Exception):
    """表示用户输入、索引或仓库状态不满足归档合同。"""


@dataclass(frozen=True)
class CommandResult:
    """保存外部命令结果。

    Attributes:
        returncode: 进程退出码。
        stdout: 标准输出文本。
        stderr: 标准错误文本。
    """

    returncode: int
    stdout: str
    stderr: str


def run_command(args: Sequence[str], cwd: Path, check: bool = True) -> CommandResult:
    """运行不经过 shell 的外部命令。

    Args:
        args: 命令及参数数组。
        cwd: 命令工作目录。
        check: 是否在非零退出时抛出 ArchiveError。

    Returns:
        包含退出码和输出的 CommandResult。
    """

    completed = subprocess.run(
        list(args),
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    result = CommandResult(completed.returncode, completed.stdout, completed.stderr)
    if check and result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "命令执行失败"
        raise ArchiveError(f"{' '.join(args)}: {message}")
    return result


def find_repo_root(start: Path) -> Path:
    """向上查找 Git 仓库根目录。

    Args:
        start: 搜索起点，可以是文件或目录。

    Returns:
        解析后的仓库根目录。
    """

    current = start.resolve()
    if current.is_file():
        current = current.parent
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    raise ArchiveError(f"未找到 Git 仓库根目录: {start}")


def normalize_repo_path(value: str, field: str, allow_archive: bool = True) -> str:
    """校验并规范化仓库相对 POSIX 路径。

    Args:
        value: 待校验的路径文本。
        field: 错误消息使用的字段名。
        allow_archive: 是否允许路径位于 archive 目录。

    Returns:
        规范化后的 POSIX 路径。
    """

    if not isinstance(value, str) or not value.strip():
        raise ArchiveError(f"{field} 必须是非空字符串")
    raw = value.strip().replace("\\", "/")
    path = PurePosixPath(raw)
    if path.is_absolute() or raw.startswith("/"):
        raise ArchiveError(f"{field} 必须是仓库相对路径: {value}")
    if any(part in {"", ".", ".."} for part in path.parts):
        raise ArchiveError(f"{field} 包含不安全路径片段: {value}")
    if path.parts[0] == ".git":
        raise ArchiveError(f"{field} 不得位于 .git: {value}")
    if not allow_archive and path.parts[0] == "archive":
        raise ArchiveError(f"源路径不得已经位于 archive: {value}")
    return path.as_posix()


def path_anchor(value: str) -> str:
    """移除索引路径末尾的递归通配符。

    Args:
        value: 已规范化的索引路径。

    Returns:
        用于文件系统检查的实际路径。
    """

    return value[:-3] if value.endswith("/**") else value


def validate_replacement(value: Any, entry_id: str) -> dict[str, Any]:
    """校验替代入口或恢复说明。

    Args:
        value: replacement 原始对象。
        entry_id: 所属索引项 ID。

    Returns:
        规范化后的 replacement 对象。
    """

    if not isinstance(value, dict):
        raise ArchiveError(f"{entry_id}.replacement 必须是对象")
    kind = value.get("kind")
    if kind == "note":
        text = value.get("text")
        if not isinstance(text, str) or not text.strip():
            raise ArchiveError(f"{entry_id}.replacement.text 必须是非空字符串")
        return {"kind": "note", "text": text.strip()}
    if kind == "path":
        target = normalize_repo_path(value.get("target", ""), f"{entry_id}.replacement.target")
        text = value.get("text", target)
        if not isinstance(text, str) or not text.strip():
            raise ArchiveError(f"{entry_id}.replacement.text 必须是非空字符串")
        return {"kind": "path", "target": target, "text": text.strip()}
    if kind == "paths":
        items = value.get("items")
        note = value.get("note")
        if not isinstance(items, list) or not items:
            raise ArchiveError(f"{entry_id}.replacement.items 必须是非空数组")
        normalized_items = []
        for index, item in enumerate(items):
            normalized = validate_replacement(
                {"kind": "path", **item} if isinstance(item, dict) else item,
                f"{entry_id}.replacement.items[{index}]",
            )
            normalized.pop("kind", None)
            normalized_items.append(normalized)
        result: dict[str, Any] = {"kind": "paths", "items": normalized_items}
        if note is not None:
            if not isinstance(note, str) or not note.strip():
                raise ArchiveError(f"{entry_id}.replacement.note 必须是非空字符串")
            result["note"] = note.strip()
        return result
    raise ArchiveError(f"{entry_id}.replacement.kind 必须是 note、path 或 paths")


def validate_index(data: Any) -> dict[str, Any]:
    """校验并稳定排序归档索引。

    Args:
        data: 从 JSON 解析得到的对象。

    Returns:
        规范化且按 batch、source 排序的索引。
    """

    if not isinstance(data, dict) or data.get("schemaVersion") != SCHEMA_VERSION:
        raise ArchiveError(f"schemaVersion 必须为 {SCHEMA_VERSION}")
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise ArchiveError("entries 必须是数组")

    seen_ids: set[str] = set()
    seen_sources: set[str] = set()
    seen_archives: set[str] = set()
    normalized_entries: list[dict[str, Any]] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ArchiveError(f"entries[{index}] 必须是对象")
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", entry_id):
            raise ArchiveError(f"entries[{index}].id 必须使用小写字母、数字和短横线")
        batch = entry.get("batch")
        if not isinstance(batch, int) or isinstance(batch, bool) or batch < 1:
            raise ArchiveError(f"{entry_id}.batch 必须是正整数")
        source = normalize_repo_path(entry.get("source", ""), f"{entry_id}.source", False)
        archive = normalize_repo_path(entry.get("archive", ""), f"{entry_id}.archive")
        expected_archive = f"archive/{source}"
        if archive != expected_archive:
            raise ArchiveError(f"{entry_id}.archive 必须为 {expected_archive}")
        reason = entry.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            raise ArchiveError(f"{entry_id}.reason 必须是非空字符串")
        if entry_id in seen_ids or source in seen_sources or archive in seen_archives:
            raise ArchiveError(f"索引存在重复 ID 或路径: {entry_id}")
        seen_ids.add(entry_id)
        seen_sources.add(source)
        seen_archives.add(archive)
        normalized_entries.append(
            {
                "id": entry_id,
                "batch": batch,
                "source": source,
                "archive": archive,
                "reason": reason.strip(),
                "replacement": validate_replacement(entry.get("replacement"), entry_id),
            }
        )
    normalized_entries.sort(key=lambda item: (item["batch"], item["source"], item["id"]))
    return {"schemaVersion": SCHEMA_VERSION, "entries": normalized_entries}


def load_index(path: Path) -> dict[str, Any]:
    """读取并校验 JSON 索引。

    Args:
        path: 索引文件路径。

    Returns:
        规范化后的索引。
    """

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ArchiveError(f"索引不存在: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ArchiveError(f"索引 JSON 无效: {exc}") from exc
    return validate_index(data)


def write_index_atomic(path: Path, data: dict[str, Any]) -> None:
    """以原子替换方式写入稳定格式的 JSON 索引。

    Args:
        path: 索引目标路径。
        data: 已校验的索引对象。

    Returns:
        无返回值。
    """

    normalized = validate_index(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(normalized, ensure_ascii=False, indent=2) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def make_entry_id(batch: int, source: str) -> str:
    """根据批次和源路径生成稳定索引 ID。

    Args:
        batch: 归档批次。
        source: 规范化源路径。

    Returns:
        小写短横线形式的索引 ID。
    """

    slug = re.sub(r"[^a-z0-9]+", "-", source.lower()).strip("-") or "item"
    return f"batch-{batch}-{slug}"


def build_replacement(args: argparse.Namespace) -> dict[str, Any]:
    """从 CLI 参数构造 replacement 对象。

    Args:
        args: argparse 解析结果。

    Returns:
        可写入索引的 replacement 对象。
    """

    if args.replacement_note:
        return {"kind": "note", "text": args.replacement_note}
    if args.replacement_path:
        return {
            "kind": "path",
            "target": normalize_repo_path(args.replacement_path, "replacement-path"),
            "text": args.replacement_text or args.replacement_path,
        }
    raise ArchiveError("必须提供 --replacement-note 或 --replacement-path")


def find_references(repo_root: Path, source: str) -> list[str]:
    """查找源路径在活动仓库内容中的文本引用。

    Args:
        repo_root: Git 仓库根目录。
        source: 规范化源路径。

    Returns:
        排除源对象、冷归档和历史任务后的引用行。
    """

    result = run_command(["git", "grep", "-n", "-F", "--", source], repo_root, check=False)
    if result.returncode not in {0, 1}:
        raise ArchiveError(result.stderr.strip() or "git grep 执行失败")
    source_anchor = path_anchor(source)
    references = []
    for line in result.stdout.splitlines():
        file_path = line.split(":", 1)[0]
        if file_path == source_anchor or file_path.startswith(f"{source_anchor}/"):
            continue
        if file_path.startswith("archive/") or file_path.startswith(".trellis/tasks/archive/"):
            continue
        references.append(line)
    return references


def build_plan(
    repo_root: Path, index: dict[str, Any], sources: Sequence[str], args: argparse.Namespace
) -> dict[str, Any]:
    """构造不修改工作区的归档计划。

    Args:
        repo_root: Git 仓库根目录。
        index: 已校验索引。
        sources: 用户指定的源路径。
        args: 包含批次、原因和替代入口的 CLI 参数。

    Returns:
        包含候选项和引用风险的计划对象。
    """

    if args.batch < 1:
        raise ArchiveError("--batch 必须是正整数")
    replacement = build_replacement(args)
    indexed_sources = {entry["source"] for entry in index["entries"]}
    indexed_archives = {entry["archive"] for entry in index["entries"]}
    planned: list[dict[str, Any]] = []
    seen_sources: set[str] = set()
    for raw_source in sources:
        source = normalize_repo_path(raw_source, "source", False)
        archive = f"archive/{source}"
        if source in seen_sources or source in indexed_sources or archive in indexed_archives:
            raise ArchiveError(f"候选已重复或已归档: {source}")
        seen_sources.add(source)
        source_path = repo_root / PurePosixPath(source)
        target_path = repo_root / PurePosixPath(archive)
        if not source_path.exists():
            raise ArchiveError(f"源路径不存在: {source}")
        if target_path.exists():
            raise ArchiveError(f"归档目标已存在: {archive}")
        tracked = run_command(["git", "ls-files", "--error-unmatch", "--", source], repo_root, check=False)
        if tracked.returncode != 0:
            # 目录本身不会被 ls-files --error-unmatch 命中，需检查其子文件。
            tracked = run_command(["git", "ls-files", "--", source], repo_root, check=False)
        if not tracked.stdout.strip():
            raise ArchiveError(f"源路径没有 Git 跟踪文件: {source}")
        entry = {
            "id": make_entry_id(args.batch, source),
            "batch": args.batch,
            "source": source,
            "archive": archive,
            "reason": args.reason.strip(),
            "replacement": replacement,
        }
        validate_index({"schemaVersion": SCHEMA_VERSION, "entries": [entry]})
        planned.append({"entry": entry, "references": find_references(repo_root, source)})
    return {"repoRoot": str(repo_root), "items": planned}


def check_repository(repo_root: Path, index: dict[str, Any]) -> list[str]:
    """检查索引记录与仓库文件系统状态是否一致。

    Args:
        repo_root: Git 仓库根目录。
        index: 已校验索引。

    Returns:
        发现的问题列表；空列表表示通过。
    """

    errors: list[str] = []
    for entry in index["entries"]:
        source_anchor = repo_root / PurePosixPath(path_anchor(entry["source"]))
        archive_anchor = repo_root / PurePosixPath(path_anchor(entry["archive"]))
        if source_anchor.exists():
            errors.append(f"源路径仍存在: {entry['source']}")
        if not archive_anchor.exists():
            errors.append(f"归档路径不存在: {entry['archive']}")
        tracked = run_command(
            ["git", "ls-files", "--", path_anchor(entry["archive"])],
            repo_root,
            check=False,
        )
        if tracked.returncode != 0 or not tracked.stdout.strip():
            errors.append(f"归档路径没有 Git 跟踪文件: {entry['archive']}")
        ignored = run_command(
            ["git", "check-ignore", "-q", "--", path_anchor(entry["archive"])],
            repo_root,
            check=False,
        )
        if ignored.returncode == 0:
            errors.append(f"归档路径被 Git ignore: {entry['archive']}")
        elif ignored.returncode not in {1}:
            errors.append(f"无法检查 Git ignore: {entry['archive']}")
    return errors


def execute_archive(repo_root: Path, index_path: Path, index: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    """执行 Git 移动并原子更新索引，失败时尽力回滚移动。

    Args:
        repo_root: Git 仓库根目录。
        index_path: JSON 索引路径。
        index: 当前已校验索引。
        plan: build_plan 生成的计划。

    Returns:
        更新后的索引对象。
    """

    moved: list[tuple[str, str]] = []
    try:
        for item in plan["items"]:
            entry = item["entry"]
            target_parent = (repo_root / PurePosixPath(entry["archive"])).parent
            target_parent.mkdir(parents=True, exist_ok=True)
            run_command(["git", "mv", "--", entry["source"], entry["archive"]], repo_root)
            moved.append((entry["source"], entry["archive"]))
        updated = {
            "schemaVersion": SCHEMA_VERSION,
            "entries": [*index["entries"], *(item["entry"] for item in plan["items"])],
        }
        write_index_atomic(index_path, updated)
        return validate_index(updated)
    except Exception as exc:
        rollback_errors: list[str] = []
        for source, archive in reversed(moved):
            rollback = run_command(["git", "mv", "--", archive, source], repo_root, check=False)
            if rollback.returncode != 0:
                rollback_errors.append(f"{archive} -> {source}: {rollback.stderr.strip()}")
        suffix = f"；回滚失败: {'; '.join(rollback_errors)}" if rollback_errors else "；已回滚已完成移动"
        raise ArchiveError(f"归档执行失败: {exc}{suffix}") from exc


def add_archive_arguments(parser: argparse.ArgumentParser) -> None:
    """为 plan/archive 子命令注册共享参数。

    Args:
        parser: 目标 argparse parser。

    Returns:
        无返回值。
    """

    parser.add_argument("sources", nargs="+", help="待归档的仓库相对路径")
    parser.add_argument("--batch", type=int, required=True, help="正整数归档批次")
    parser.add_argument("--reason", required=True, help="归档原因")
    replacement = parser.add_mutually_exclusive_group(required=True)
    replacement.add_argument("--replacement-note", help="没有活动替代入口时的恢复说明")
    replacement.add_argument("--replacement-path", help="活动替代入口的仓库相对路径")
    parser.add_argument("--replacement-text", help="替代入口的显示说明")


def create_parser() -> argparse.ArgumentParser:
    """创建 CLI 参数解析器。

    Returns:
        配置完成的 ArgumentParser。
    """

    parser = argparse.ArgumentParser(description="安全规划、执行并校验 Git 仓库冷归档")
    parser.add_argument("--repo-root", type=Path, help="目标 Git 仓库根目录，默认从当前目录向上查找")
    parser.add_argument("--index", default=str(DEFAULT_INDEX_PATH), help="相对仓库根的索引路径")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check", help="校验索引和归档路径状态")
    plan_parser = subparsers.add_parser("plan", help="输出归档计划，不修改文件")
    add_archive_arguments(plan_parser)
    archive_parser = subparsers.add_parser("archive", help="执行 Git 移动并更新索引")
    add_archive_arguments(archive_parser)
    archive_parser.add_argument("--execute", action="store_true", help="显式允许修改仓库")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """执行 CLI。

    Args:
        argv: 可选命令行参数，None 时读取 sys.argv。

    Returns:
        0 表示成功，2 表示输入或仓库状态错误，3 表示检查发现不一致。
    """

    parser = create_parser()
    args = parser.parse_args(argv)
    try:
        repo_root = find_repo_root(args.repo_root or Path.cwd())
        index_relative = normalize_repo_path(args.index, "index")
        index_path = repo_root / PurePosixPath(index_relative)
        index = load_index(index_path)
        if args.command == "check":
            errors = check_repository(repo_root, index)
            if errors:
                for error in errors:
                    print(error, file=sys.stderr)
                return 3
            print(json.dumps({"status": "ok", "entries": len(index["entries"])}, ensure_ascii=False))
            return 0
        plan = build_plan(repo_root, index, args.sources, args)
        if args.command == "plan":
            print(json.dumps(plan, ensure_ascii=False, indent=2))
            return 0
        if not args.execute:
            raise ArchiveError("archive 必须显式传入 --execute；请先运行 plan")
        updated = execute_archive(repo_root, index_path, index, plan)
        print(
            json.dumps(
                {"status": "archived", "entries": len(updated["entries"]), "plan": plan}, ensure_ascii=False, indent=2
            )
        )
        return 0
    except ArchiveError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
