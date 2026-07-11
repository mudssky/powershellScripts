# Repository Cold Archive Contract

## 1. Scope / Trigger

- Trigger：把已经失效、被替代或仅具历史参考价值的仓库内容迁入根 `archive/`。
- Scope：路径迁移、归档索引、活动引用修复、Git 历史追溯，以及 workspace、构建、测试、格式化、lint 和发布边界。
- 不适用：生成物、缓存、本机运行数据和仍有活动入口的兼容实现；这些内容分别由 ignore/cleanup 或活动目录合同管理。

## 2. Signatures

- 目标路径：`archive/<原始仓库相对路径>`。
- 迁移动作：`git mv <source> archive/<source>`。
- 索引：`archive/README.md`，固定字段为“批次、原路径、归档路径、原因、替代入口或恢复说明”。
- PowerShell 格式器：

```text
pwshfmt-rs <check|write> [--git-changed] [--path <path>] [--recurse]
  [--exclude-path <path>]...
```

- 根配置：`pwshfmt-rs.toml` 的 `exclude_paths = ["archive"]`。

## 3. Contracts

- `archive/` 继续由 Git 跟踪并允许普通搜索；不得通过根 `.gitignore` 隐藏。
- 归档对象使用镜像路径，不按语言或平台重新分类；同一提交中不改写归档文件正文，以提高 rename 识别和 `git log --follow` 可追溯性。
- 归档索引必须说明替代入口；没有替代入口时明确“仅供历史参考”，不得从归档路径建立新安装或运行入口。
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

## 6. Tests Required

- Rust：递归 discovery 保留活动文件并跳过 `archive/**`；Git changed discovery 做同样断言。
- Pester：PowerShell wrapper 的递归模式在无 Git 环境也验证归档排除；Git 可用时补充 changed 模式断言。
- Config：Biome、rumdl、Ruff、lint-staged 和 notebook cleanup 均有根 archive 排除证据；lint-staged 的安全扫描仍匹配归档路径。
- Repository：源路径消失、目标路径存在、未批准对象保持原位，`git check-ignore` 不命中归档文件。
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
