---
name: project-archive
description: 审计仓库中的失效、被替代或仅具历史价值的文件与目录，安全迁移到根 archive 镜像路径，并维护结构化归档索引。用于用户要求归档项目内容、清理根目录旧工具配置、检查冷归档一致性、恢复归档对象或更新 archive/index.json 时。
---

# 项目冷归档

通过 `scripts/archive_project.py` 规划、执行和校验 Git 仓库冷归档。索引唯一真源为目标仓库的 `archive/index.json`。

## 工作流

1. 读取目标仓库的项目规范、`archive/index.json` 和 Git 状态。
2. 检查候选是否已失效、已被替代或只剩历史参考价值。仍有活动代码、测试、安装或发布入口时停止归档。
3. 先运行 `plan`。检查镜像目标、Git 跟踪状态和活动引用；不要手工拼接移动命令。
4. 向用户展示候选、原因、替代入口、引用风险和回滚方式，获得明确批准。
5. 使用相同参数运行带 `--execute` 的 `archive`。脚本执行 `git mv` 并同步更新 JSON 索引。
6. 运行 `check`，再执行目标仓库规定的质量门禁。
7. 提交前检查 rename 识别和 `git diff`；不要在移动同一提交中改写归档文件正文。

## 命令

从本 skill 根目录执行：

```bash
# 指向待处理 Git 仓库根目录
REPO_ROOT="$(git rev-parse --show-toplevel)"

# 校验当前仓库索引和归档路径
python3 scripts/archive_project.py --repo-root "$REPO_ROOT" check

# 只输出计划，不修改文件
python3 scripts/archive_project.py --repo-root "$REPO_ROOT" plan old/path \
  --batch 3 \
  --reason "旧入口已停止维护" \
  --replacement-path new/path \
  --replacement-text "使用新入口"

# 获得批准后显式执行
python3 scripts/archive_project.py --repo-root "$REPO_ROOT" archive old/path \
  --batch 3 \
  --reason "旧入口已停止维护" \
  --replacement-path new/path \
  --replacement-text "使用新入口" \
  --execute
```

没有替代入口时改用：

```bash
--replacement-note "仅供历史参考"
```

## 风险边界

- 不归档生成物、缓存、secret、本机运行数据或仍有活动入口的兼容实现。
- 只接受仓库相对路径；拒绝绝对路径、`..`、`.git/` 和已经位于 `archive/` 的源路径。
- 目标固定为 `archive/<原路径>`，不按语言、平台或文件类型重分类。
- `plan` 永远不写文件；`archive` 缺少 `--execute` 时必须失败。
- 不自动修改引用、不自动提交、不删除内容，也不从归档路径建立新运行入口。
- 执行失败时先查看脚本报告的已移动路径；脚本会尽力反向移动，仍需用 `git status` 验证。

## 恢复

恢复前确认对象重新拥有明确使用场景、维护负责人和质量门禁。使用反向 `git mv` 恢复原路径，删除对应 `archive/index.json` 条目，然后运行 `check` 和项目质量门禁。
