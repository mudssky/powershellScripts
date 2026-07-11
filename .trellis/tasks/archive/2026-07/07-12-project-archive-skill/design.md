# 项目冷归档技能与索引自动化设计

## 1. 组件边界

| 组件 | 职责 |
|---|---|
| `.agents/skills/project-archive/SKILL.md` | 面向 agent 的判断流程、风险边界和脚本路由 |
| `.agents/skills/project-archive/scripts/archive_project.py` | JSON 校验、计划、Git 移动和索引更新 |
| `.agents/skills/project-archive/tests/test_archive_project.py` | 核心逻辑、CLI 和危险操作保护测试 |
| `archive/index.json` | 归档记录唯一真源 |

脚本从 `--repo-root` 定位目标仓库；默认使用当前目录向上查找 `.git`，不得依赖 skill 安装路径推断项目根。

## 2. 索引合同

采用 JSON，避免引入 YAML/TOML 第三方解析依赖。顶层包含 schema 版本和 entries：

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "id": "batch-2-vercel-project",
      "batch": 2,
      "source": ".vercel/project.json",
      "archive": "archive/.vercel/project.json",
      "reason": "本仓已停止使用 Vercel 部署",
      "replacement": {
        "kind": "note",
        "text": "仅保留旧项目标识，无活动替代入口"
      }
    }
  ]
}
```

`replacement.kind` 支持：

- `path`：`target` 为仓库相对路径，生成可点击链接；可选 `text` 控制显示文字。
- `note`：`text` 为纯文本恢复说明。

校验规则：ID、source、archive 唯一；路径不得绝对化或包含 `..`；archive 必须严格等于 `archive/<source>`；batch 为正整数；字符串不得为空。

## 3. CLI 合同

```text
archive_project.py check
archive_project.py plan <source>... --batch <n> --reason <text> [replacement options]
archive_project.py archive <source>... --batch <n> --reason <text> --execute [replacement options]
```

- `check` 运行索引 schema、归档目标存在性和源路径缺失检查。
- `plan` 检查源路径、计算镜像目标、运行仓库引用搜索并输出 JSON 草案；不写配置、不移动文件。
- `archive` 复用 plan，缺少 `--execute` 时拒绝写入。执行顺序为校验全部候选、逐项 `git mv`、原子更新索引；任一步失败则返回非零，并报告已完成动作以便人工回滚。

首版一次调用中的候选共享 batch、reason 和 replacement。语义不同的对象应分开调用，避免为了批量能力设计复杂输入 DSL；需要复杂批次时可先编辑 JSON，再运行 `check`。

## 4. 安全与 Git 边界

- 只允许仓库内相对路径，拒绝 `archive/` 内源路径和 `.git/`。
- 目标存在、源缺失、source/target 嵌套冲突时拒绝执行。
- 使用参数数组调用 `git mv -- <source> <target>`，不经过 shell。
- plan 搜索引用时复用 `git grep -n -- <tokens>`；历史 `.trellis/tasks/archive/**` 命中只报告，不自动改写。
- 不自动提交，不自动删除，不改写归档文件正文。
- 索引写入使用临时文件后原子替换。

## 5. Skill 结构

使用 `skill-creator` 的初始化脚本生成 `.agents/skills/project-archive`，只创建实际需要的 `scripts/`、`tests/` 和可选 `agents/openai.yaml`。SKILL 主文档保持中文、命令式和精简；详细 schema 由脚本 `--help` 与 `archive/index.json` 自描述，不另建重复 reference。

## 6. 兼容性与迁移

- 首次迁移将现有 README 的 8 行人工索引无损写入 JSON，然后删除 README。
- `.trellis/spec/infra/repository-archive.md` 的索引真源从 README 更新为 JSON，并删除对 Markdown 索引的要求。
- 仓库内指向 `archive/README.md` 的活动链接需要迁移为 `archive/index.json`；历史任务记录保持不变。
- 回滚可删除新 skill 和 JSON，并恢复旧 README；归档内容本身不受影响。

## 7. 验证策略

- 结构：skill audit 和 quick validate。
- 资源：`--help`、compileall、unittest。
- 行为：临时 Git 仓库覆盖 plan、archive、check、失败和幂等路径。
- 项目：`pnpm qa`，并定向运行脚本对当前仓库执行 `check`。
