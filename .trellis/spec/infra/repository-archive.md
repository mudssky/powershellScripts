# Repository Cold Archive Contract

## 1. Scope / Trigger

- Trigger：把已经失效、被替代或仅具历史参考价值的仓库内容迁入根 `archive/`。
- Scope：路径迁移、归档索引、活动引用修复、Git 历史追溯，以及 workspace、构建、测试、格式化、lint 和发布边界。
- 不适用：生成物、缓存、本机运行数据和仍有活动入口的兼容实现；这些内容分别由 ignore/cleanup 或活动目录合同管理。

## 2. Signatures

- 目标路径：`archive/<原始仓库相对路径>`。
- 迁移动作：`git mv <source> archive/<source>`。
- 索引：`archive/index.json`，固定字段为 schema 版本、稳定 ID、批次、原路径、归档路径、原因、替代入口或恢复说明。
- 自动化入口：`.agents/skills/project-archive/scripts/archive_project.py <check|plan|archive>`。
- PowerShell 格式器：

```text
pwshfmt-rs <check|write> [--git-changed] [--path <path>] [--recurse]
  [--exclude-path <path>]...
```

- 根配置：`pwshfmt-rs.toml` 的 `exclude_paths = ["archive"]`。

## 3. Contracts

- `archive/` 继续由 Git 跟踪并允许普通搜索；不得通过根 `.gitignore` 隐藏。
- 归档对象使用镜像路径，不按语言或平台重新分类；同一提交中不改写归档文件正文，以提高 rename 识别和 `git log --follow` 可追溯性。
- `archive/index.json` 是归档事实唯一真源，不维护并行 Markdown 索引。
- 每个索引项必须使用稳定 ID，说明替代入口；没有替代入口时明确“仅供历史参考”，不得从归档路径建立新安装或运行入口。
- 索引路径必须使用仓库相对 POSIX 形式，且归档路径严格等于 `archive/<原路径>`。
- 新归档先运行 `plan`；只有获得明确批准后才能运行带 `--execute` 的 `archive`。执行入口必须使用 `git mv` 并同步更新 JSON 索引。
- 批量归档前必须检查 `make_entry_id(batch, source)` 的结果是否唯一。稳定 ID 只保留 ASCII 字母和数字，多个中文文件可能折叠为同一父路径 slug；发生冲突时保持原路径不变，把冲突项分配到后续批次。
- 目录归档前必须检查源目录内的 ignored/untracked 文件。`git mv` 会随目录移动这些文件，但它们不属于 Git 索引事实；应先移到仓库外的可追溯备份位置，不能让它们被动进入 `archive/`。
- 根 `archive/` 默认退出 pnpm workspace、Turbo、Pester/Vitest、Biome、rumdl、Ruff、lint-staged、notebook cleanup 和 PowerShell formatter。
- betterleaks 等 secret 安全扫描继续覆盖归档文件，因为内容仍会进入 Git 历史。
- Biome 使用 `files.includes` force-ignore：`["**", "!!archive"]`；普通 `!` 只排除处理但仍可能被 scanner 索引，不满足冷归档合同。
- lint-staged 的格式化 glob 使用 `{,!(archive)/**/}*.<ext>` 形态；全文件安全扫描 pattern 保持 `*`。
- `pwshfmt-rs` 的 `exclude_paths` 同时作用于显式路径、递归遍历和 Git changed discovery；目录遍历必须在进入归档子树前剪枝。

## 4. Validation & Error Matrix

| 条件 | 预期结果 |
|---|---|
| 候选仍有活动代码、测试或安装引用 | 不迁移，恢复为待确认状态 |
| 目标不是 `archive/<原路径>` | 拒绝迁移，先修正镜像路径 |
| `archive` 未显式传入 `--execute` | 拒绝修改，要求先审阅 `plan` 输出 |
| 索引存在重复 ID、源路径或归档路径 | 校验失败，不执行移动 |
| 同批中文路径生成相同稳定 ID | 拆到不同批次后重新 `plan`，不得改名规避冲突 |
| 源目录包含 ignored/untracked 文件 | 执行前移出仓库并记录备份位置，只归档 Git 跟踪内容 |
| `git check-ignore archive/...` 命中 | 配置错误；归档必须保持可跟踪 |
| 显式执行 Biome 检查归档文件 | 报告文件被配置忽略；“No files were processed” 可作为排除证据 |
| PowerShell formatter 显式传入 `archive` | 成功快速退出，不处理文件 |
| Linux Pester 镜像缺少 Git | 递归排除测试仍执行；仅 Git changed wrapper 用例明确 Skip |
| 移动后发现真实外部入口 | 反向 `git mv` 对应单项，不放宽整个归档目录的排除 |

## 5. Good / Base / Bad Cases

- Good：`deprecated/tool.ps1` 移到 `archive/deprecated/tool.ps1`，索引指向活动替代脚本，formatter 与 lint 不处理它，betterleaks 仍扫描暂存内容。
- Base：没有替代入口的旧配置快照进入镜像路径，索引写明仅供历史回退参考。
- Bad：把 `archive/` 加入 `.gitignore`，导致新索引和后续批次无法正常跟踪。
- Bad：使用 `!!**/archive` 无差别排除所有同名子目录；根冷归档合同只要求排除顶级 `archive/`。
- Bad：移动同时格式化旧脚本正文，降低 Git rename 识别率并引入无意义维护。
- Bad：直接归档包含 `.env`、本地备份或 ignored 文档的整个目录，导致未跟踪内容被 `git mv` 一并带入 `archive/`。
- Good：先用 `git ls-files --others --ignored --exclude-standard <source>` 审计未跟踪内容，移到仓库外备份，再执行已批准的归档计划。

## 6. Tests Required

- Rust：递归 discovery 保留活动文件并跳过 `archive/**`；Git changed discovery 做同样断言。
- Pester：PowerShell wrapper 的递归模式在无 Git 环境也验证归档排除；Git 可用时补充 changed 模式断言。
- Config：Biome、rumdl、Ruff、lint-staged 和 notebook cleanup 均有根 archive 排除证据；lint-staged 的安全扫描仍匹配归档路径。
- Repository：`archive_project.py check` 通过；源路径消失、目标路径存在、未批准对象保持原位，`git check-ignore` 不命中归档文件。
- Repository：批量 plan 的稳定 ID 无重复；目录候选的 ignored/untracked 清单为空，或每个对象都有仓库外备份记录。
- Gate：`pnpm qa` 与 `pnpm test:pwsh:all` 通过；提交后抽查 `git log --follow -- archive/<file>`。

## 7. Wrong vs Correct

### Wrong

```gitignore
/archive/
```

```json
{
  "files": {
    "includes": ["**", "!archive"]
  }
}
```

问题：Git 不再自然接纳后续归档文件；Biome 普通 ignore 也不能保证 scanner 完全退出该目录。

### Correct

```json
{
  "files": {
    "includes": ["**", "!!archive"]
  }
}
```

```toml
exclude_paths = ["archive"]
```

理由：归档仍是可跟踪源码的一部分，但维护工具通过各自的显式合同跳过它。

### 中文路径与未跟踪文件

#### Wrong

```bash
python3 archive_project.py archive docs/中文一.md docs/中文二.md \
  --batch 7 --reason "历史资料" --replacement-note "仅供历史参考" --execute
```

问题：两个路径可能生成同一个 ASCII 稳定 ID；如果源目录还含 ignored 文件，目录移动也会把它们一起带入归档。

#### Correct

```bash
git ls-files --others --ignored --exclude-standard docs
python3 archive_project.py plan docs/中文一.md --batch 7 \
  --reason "历史资料" --replacement-note "仅供历史参考"
python3 archive_project.py plan docs/中文二.md --batch 8 \
  --reason "历史资料" --replacement-note "仅供历史参考"
```

理由：先隔离未跟踪内容，再用不同批次保持稳定 ID 唯一，同时不改变原文件名和镜像路径。
