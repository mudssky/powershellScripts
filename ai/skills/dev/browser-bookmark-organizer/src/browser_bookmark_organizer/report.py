"""Markdown、HTML 与 JSON 报告渲染。"""

from __future__ import annotations

from collections import Counter
from typing import Any

from browser_bookmark_organizer.clock import now_local_iso
from browser_bookmark_organizer.link_checker import LinkCheckOptions, LinkCheckResult
from browser_bookmark_organizer.models import Bookmark, BookmarkAnalysis, Folder
from browser_bookmark_organizer.templating import read_static_text, render_template


def build_report_payload(
    analysis: BookmarkAnalysis,
    link_results: list[LinkCheckResult] | None = None,
    link_options: LinkCheckOptions | None = None,
) -> dict[str, Any]:
    """构造 JSON 友好的报告数据。

    Args:
        analysis: 离线分析结果。
        link_results: 可选链接检测结果。
        link_options: 可选链接检测配置。

    Returns:
        dict[str, Any]: 可直接传给 `json.dump` 的报告数据。
    """

    return {
        "generatedAt": now_local_iso(),
        "input": analysis.input_path,
        "summary": {
            "folderCount": len(analysis.folders),
            "bookmarkCount": len(analysis.bookmarks),
            "maxDepth": analysis.max_depth,
            "duplicateGroupCount": len(analysis.duplicate_groups),
            "emptyFolderCount": len(analysis.empty_folders),
            "suspiciousTitleCount": len(analysis.suspicious_titles),
        },
        "schemes": counts_to_items(analysis.scheme_counts, "scheme"),
        "domains": counts_to_items(analysis.domain_counts, "domain"),
        "duplicates": [
            {
                "normalizedUrl": group.normalized_url,
                "count": len(group.bookmarks),
                "items": [bookmark_to_dict(bookmark) for bookmark in group.bookmarks],
            }
            for group in analysis.duplicate_groups
        ],
        "emptyFolders": [folder_to_dict(folder) for folder in analysis.empty_folders],
        "dedupAtRiskFolders": [folder_to_dict(folder) for folder in analysis.dedup_at_risk_folders],
        "suspiciousTitles": [
            {
                "reason": item.reason,
                "bookmark": bookmark_to_dict(item.bookmark),
            }
            for item in analysis.suspicious_titles
        ],
        "linkChecks": build_link_payload(link_results, link_options),
    }


def build_link_payload(
    link_results: list[LinkCheckResult] | None,
    link_options: LinkCheckOptions | None,
) -> dict[str, Any]:
    """构造链接检测 JSON 数据。

    Args:
        link_results: 可选链接检测结果。
        link_options: 可选链接检测配置。

    Returns:
        dict[str, Any]: 链接检测报告分段。
    """

    if link_results is None:
        return {"enabled": False}

    status_counter: Counter[str] = Counter()
    for result in link_results:
        status_counter[link_status_bucket(result)] += 1

    return {
        "enabled": True,
        "options": {
            "timeout": link_options.timeout if link_options else None,
            "followRedirects": link_options.follow_redirects if link_options else None,
            "concurrency": link_options.concurrency if link_options else None,
            "delay": link_options.delay if link_options else None,
            "maxLinks": link_options.max_links if link_options else None,
            "checkPrivateLinks": link_options.check_private_links if link_options else None,
            "networkContext": link_options.network_context if link_options else None,
        },
        "summary": dict(status_counter.most_common()),
        "items": [link_result_to_dict(result) for result in link_results],
    }


def render_markdown_report(
    analysis: BookmarkAnalysis,
    link_results: list[LinkCheckResult] | None = None,
    link_options: LinkCheckOptions | None = None,
) -> str:
    """渲染 Markdown 报告。

    Args:
        analysis: 离线分析结果。
        link_results: 可选链接检测结果。
        link_options: 可选链接检测配置。

    Returns:
        str: Markdown 报告文本。
    """

    lines = [
        "# 浏览器书签整理报告",
        "",
        f"- 输入文件：`{analysis.input_path}`",
        f"- 生成时间：`{now_local_iso()}`",
        "",
        "## 摘要",
        "",
        "| 指标 | 数量 |",
        "|---|---:|",
        f"| 文件夹 | {len(analysis.folders)} |",
        f"| 书签 | {len(analysis.bookmarks)} |",
        f"| 最大目录深度 | {analysis.max_depth} |",
        f"| 重复 URL 组 | {len(analysis.duplicate_groups)} |",
        f"| 空文件夹 | {len(analysis.empty_folders)} |",
        f"| 可疑标题 | {len(analysis.suspicious_titles)} |",
        "",
    ]
    lines.extend(render_counts("URL Scheme 分布", "Scheme", analysis.scheme_counts, limit=20))
    lines.extend(render_counts("Domain Top 30", "Domain", analysis.domain_counts, limit=30))
    lines.extend(render_duplicates(analysis))
    lines.extend(render_empty_folders(analysis))
    lines.extend(render_dedup_at_risk_folders(analysis))
    lines.extend(render_suspicious_titles(analysis))
    lines.extend(render_link_section(link_results, link_options))
    return "\n".join(lines).rstrip() + "\n"


def render_html_report(payload: dict[str, Any]) -> str:
    """渲染精美 HTML 报告。

    Args:
        payload: `build_report_payload` 生成的 JSON 友好数据。

    Returns:
        str: 可离线打开的完整 HTML 报告。
    """

    link_checks = payload.get("linkChecks", {})
    status_items = [
        {"status": str(key), "count": value}
        for key, value in (link_checks.get("summary") or {}).items()
    ] or [{"status": "未启用", "count": 0}]

    return render_template(
        "report.html",
        payload=payload,
        summary=payload["summary"],
        generated_at=payload.get("generatedAt", ""),
        input_path=payload.get("input", ""),
        link_checks=link_checks,
        status_items=status_items,
        domain_bars=build_bar_items(payload.get("domains", [])[:10], "domain"),
        issue_items=build_html_issue_items(payload),
        duplicate_items=payload.get("duplicates", [])[:20],
        report_css=read_static_text("report.css"),
    )


def build_bar_items(items: list[dict[str, Any]], key_name: str) -> list[dict[str, Any]]:
    """构造轻量条形图数据。

    Args:
        items: 计数项列表。
        key_name: 名称字段。

    Returns:
        list[dict[str, Any]]: 带宽度百分比的条形图数据。
    """

    if not items:
        return []
    max_count = max(int(item["count"]) for item in items) or 1
    rows: list[dict[str, Any]] = []
    for item in items:
        count = int(item["count"])
        rows.append(
            {
                "label": str(item[key_name]),
                "count": count,
                "width": max(4, round(count / max_count * 100)),
            }
        )
    return rows


def build_html_issue_items(payload: dict[str, Any]) -> list[dict[str, str]]:
    """构造 HTML 报告中的重点问题列表。

    Args:
        payload: 报告 payload。

    Returns:
        list[dict[str, str]]: 问题展示数据。
    """

    rows: list[dict[str, str]] = []
    for item in payload.get("suspiciousTitles", [])[:30]:
        bookmark = item["bookmark"]
        rows.append(
            issue_item(
                "可疑标题",
                bookmark.get("title") or "(空标题)",
                bookmark.get("folderDisplayPath", ""),
                item.get("reason", ""),
                "warn",
            )
        )
    for item in payload.get("emptyFolders", [])[:30]:
        rows.append(
            issue_item("空文件夹", item["displayPath"], item["displayPath"], "empty_folder", "warn")
        )
    for item in payload.get("duplicates", [])[:30]:
        rows.append(
            issue_item(
                "重复 URL", item["normalizedUrl"], "多个目录", f"{item['count']} items", "warn"
            )
        )
    for item in (payload.get("linkChecks", {}).get("items") or [])[:200]:
        if (
            item.get("errorCategory")
            or item.get("skippedReason") == "context_required"
            or (item.get("statusCode") and item["statusCode"] >= 400)
        ):
            rows.append(
                issue_item(
                    "上下文链接" if item.get("skippedReason") == "context_required" else "链接异常",
                    item.get("title") or item.get("url", ""),
                    item.get("folderDisplayPath", ""),
                    item.get("networkHint") or item.get("bucket", ""),
                    "warn" if item.get("skippedReason") == "context_required" else "danger",
                )
            )
    return rows[:80]


def issue_item(kind: str, target: str, location: str, status: str, level: str) -> dict[str, str]:
    """构造单个重点问题展示对象。

    Args:
        kind: 问题类型。
        target: 问题对象。
        location: 所在位置。
        status: 状态或原因。
        level: 视觉等级。

    Returns:
        dict[str, str]: 问题展示对象。
    """

    return {
        "kind": kind,
        "target": str(target),
        "location": str(location),
        "status": str(status),
        "level": level,
    }


def render_counts(title: str, label: str, counts: dict[str, int], limit: int) -> list[str]:
    """渲染计数表格。

    Args:
        title: Markdown 小节标题。
        label: 第一列表头。
        counts: 名称到数量的映射。
        limit: 最多展示行数。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = [f"## {title}", "", f"| {label} | 数量 |", "|---|---:|"]
    for key, count in list(counts.items())[:limit]:
        lines.append(f"| {md_cell(key)} | {count} |")
    if not counts:
        lines.append("| 无 | 0 |")
    lines.append("")
    return lines


def render_duplicates(analysis: BookmarkAnalysis) -> list[str]:
    """渲染重复 URL 分组。

    Args:
        analysis: 离线分析结果。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = ["## 重复 URL", ""]
    if not analysis.duplicate_groups:
        return [*lines, "未发现规范化 URL 重复项。", ""]
    for group in analysis.duplicate_groups[:50]:
        lines.append(f"### {md_inline(group.normalized_url)}")
        lines.append("")
        lines.append("| 标题 | 目录 | 原始 URL |")
        lines.append("|---|---|---|")
        for bookmark in group.bookmarks:
            lines.append(
                f"| {md_cell(bookmark.title)} | {md_cell(bookmark.folder_display_path)} "
                f"| {md_cell(bookmark.url)} |"
            )
        lines.append("")
    return lines


def render_empty_folders(analysis: BookmarkAnalysis) -> list[str]:
    """渲染空文件夹列表。

    Args:
        analysis: 离线分析结果。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = ["## 空文件夹", ""]
    if not analysis.empty_folders:
        return [*lines, "未发现空文件夹。", ""]
    lines.extend(f"- `{folder.display_path}`" for folder in analysis.empty_folders[:100])
    lines.append("")
    return lines


def render_dedup_at_risk_folders(analysis: BookmarkAnalysis) -> list[str]:
    """渲染去重后可能变空的文件夹列表。

    Args:
        analysis: 离线分析结果。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = ["## 去重后可能变空的文件夹", ""]
    if not analysis.dedup_at_risk_folders:
        return [*lines, "未发现去重后会变空的文件夹。", ""]
    lines.append("以下文件夹当前包含书签，但书签全部属于重复组，去重后会变空：")
    lines.append("")
    lines.extend(f"- `{folder.display_path}`" for folder in analysis.dedup_at_risk_folders[:100])
    lines.append("")
    return lines


def render_suspicious_titles(analysis: BookmarkAnalysis) -> list[str]:
    """渲染可疑标题列表。

    Args:
        analysis: 离线分析结果。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = ["## 可疑标题", ""]
    if not analysis.suspicious_titles:
        return [*lines, "未发现空标题或疑似乱码标题。", ""]
    lines.append("| 原因 | 标题 | 目录 | URL |")
    lines.append("|---|---|---|---|")
    for item in analysis.suspicious_titles[:100]:
        bookmark = item.bookmark
        lines.append(
            f"| {md_cell(item.reason)} | {md_cell(bookmark.title)} "
            f"| {md_cell(bookmark.folder_display_path)} | {md_cell(bookmark.url)} |"
        )
    lines.append("")
    return lines


def render_link_section(
    link_results: list[LinkCheckResult] | None,
    link_options: LinkCheckOptions | None,
) -> list[str]:
    """渲染链接检测结果。

    Args:
        link_results: 可选链接检测结果。
        link_options: 可选链接检测配置。

    Returns:
        list[str]: Markdown 行列表。
    """

    lines = ["## 链接检测", ""]
    if link_results is None:
        return [*lines, "未启用。需要联网检测时重新运行并传入 `--check-links`。", ""]

    summary = Counter(link_status_bucket(result) for result in link_results)
    lines.append(
        "已启用："
        f"timeout={link_options.timeout if link_options else 'n/a'}s，"
        f"concurrency={link_options.concurrency if link_options else 'n/a'}，"
        f"delay={link_options.delay if link_options else 'n/a'}s，"
        f"network={link_options.network_context if link_options else 'n/a'}。"
    )
    lines.append("")
    lines.append("| 状态 | 数量 |")
    lines.append("|---|---:|")
    for key, count in summary.most_common():
        lines.append(f"| {md_cell(key)} | {count} |")
    lines.append("")

    problem_results = [
        result
        for result in link_results
        if result.is_problem or result.skipped_reason == "context_required"
    ]
    if not problem_results:
        lines.append("未发现错误状态或请求异常。")
        lines.append("")
        return lines

    lines.append("### 需要关注的链接")
    lines.append("")
    lines.append("| 状态 | 网络上下文 | 标题 | 目录 | URL | 最终 URL/提示 | 耗时 |")
    lines.append("|---|---|---|---|---|---|---:|")
    for result in problem_results[:100]:
        lines.append(
            f"| {md_cell(link_status_bucket(result))} | {md_cell(result.network_context)} "
            f"| {md_cell(result.title)} "
            f"| {md_cell(folder_path_to_display(result.folder_path))} | {md_cell(result.url)} "
            f"| {md_cell(result.final_url or result.network_hint or '')} "
            f"| {result.elapsed_ms or 0}ms |"
        )
    lines.append("")
    return lines


def bookmark_to_dict(bookmark: Bookmark) -> dict[str, Any]:
    """序列化书签。

    Args:
        bookmark: 书签对象。

    Returns:
        dict[str, Any]: JSON 友好的书签数据。
    """

    return {
        "title": bookmark.title,
        "url": bookmark.url,
        "folderPath": list(bookmark.folder_path),
        "folderDisplayPath": bookmark.folder_display_path,
        "order": bookmark.order,
        "attrs": bookmark.attrs,
    }


def folder_to_dict(folder: Folder) -> dict[str, Any]:
    """序列化文件夹。

    Args:
        folder: 文件夹对象。

    Returns:
        dict[str, Any]: JSON 友好的文件夹数据。
    """

    return {
        "title": folder.title,
        "path": list(folder.path),
        "displayPath": folder.display_path,
        "directBookmarkCount": len(folder.bookmarks),
        "directFolderCount": len(folder.folders),
    }


def link_result_to_dict(result: LinkCheckResult) -> dict[str, Any]:
    """序列化链接检测结果。

    Args:
        result: 链接检测结果。

    Returns:
        dict[str, Any]: JSON 友好的链接检测数据。
    """

    return {
        "order": result.order,
        "title": result.title,
        "url": result.url,
        "folderPath": list(result.folder_path),
        "folderDisplayPath": folder_path_to_display(result.folder_path),
        "checked": result.checked,
        "skippedReason": result.skipped_reason,
        "networkContext": result.network_context,
        "networkHint": result.network_hint,
        "statusCode": result.status_code,
        "finalUrl": result.final_url,
        "errorCategory": result.error_category,
        "errorMessage": result.error_message,
        "elapsedMs": result.elapsed_ms,
        "bucket": link_status_bucket(result),
    }


def counts_to_items(counts: dict[str, int], key_name: str) -> list[dict[str, Any]]:
    """把计数字典转换为对象列表。

    Args:
        counts: 名称到数量的映射。
        key_name: 输出对象中的名称字段。

    Returns:
        list[dict[str, Any]]: JSON 友好的计数列表。
    """

    return [{key_name: key, "count": count} for key, count in counts.items()]


def link_status_bucket(result: LinkCheckResult) -> str:
    """归类链接检测状态。

    Args:
        result: 链接检测结果。

    Returns:
        str: skipped、error、http_2xx 等状态桶。
    """

    if not result.checked:
        return f"skipped:{result.skipped_reason or 'unknown'}"
    if result.error_category:
        return f"error:{result.error_category}"
    if result.status_code is None:
        return "unknown"
    return f"http_{result.status_code // 100}xx"


def folder_path_to_display(path: tuple[str, ...]) -> str:
    """把文件夹路径转换成展示字符串。

    Args:
        path: 文件夹路径元组。

    Returns:
        str: 以 `/` 拼接的展示路径。
    """

    return "/" if not path else "/" + "/".join(path)


def md_cell(value: str) -> str:
    """转义 Markdown 表格单元格。

    Args:
        value: 原始单元格文本。

    Returns:
        str: 可放入 Markdown 表格的文本。
    """

    return value.replace("|", "\\|").replace("\n", " ").strip() or " "


def md_inline(value: str) -> str:
    """转义 Markdown 行内代码片段。

    Args:
        value: 原始文本。

    Returns:
        str: 可用于行内代码的文本。
    """

    return "`" + value.replace("`", "\\`") + "`"
