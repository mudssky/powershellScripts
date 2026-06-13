# 迁移 powershellscripts-ops 到 dev skill 执行计划

## Checklist

1. 迁移目录
   - 将 `.agents/skills/repo-ops/` 移动到 `ai/skills/dev/powershellscripts-ops/`。
   - 将 `SKILL.md` frontmatter 改为 `name: powershellscripts-ops`。

2. 更新 skill 内容
   - 在 `SKILL.md` 增加全局安装态仓库定位规则：`POWERSHELLSCRIPTS_REPO` 优先，兜底 `/Users/mudssky/projects/env/powershellScripts`。
   - 将维护说明中的 `.agents/skills/repo-ops` 改为 `ai/skills/dev/powershellscripts-ops`。
   - 明确不推荐 project scope 重复安装。
   - 检查 reference 中是否还有旧路径。

3. 更新安装配置
   - 在 `ai/skills/skills.config.json` 增加 `powershellscripts-ops`，`source` 指向 `./dev/powershellscripts-ops`，`sourceType` 为 `local`。
   - 保持默认 `scope: global` 与默认 agents 不变。

4. 更新引用
   - 搜索 `.agents/skills/repo-ops`、`repo-ops skill`、`ai/skills/dev/repo-ops`、`powershellscripts-ops`。
   - 只更新活动文档、规范或 skill 维护说明；历史 archive 任务原则上不改，除非它会误导当前维护入口。

5. 校验
   - 运行 skill 校验：

```bash
python3 /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/powershellscripts-ops
```

   - 若缺少 `yaml` 依赖，改用：

```bash
uv run --with pyyaml python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/powershellscripts-ops
```

   - 运行安装器 dry-run：

```bash
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name powershellscripts-ops -DryRun
```

   - 代码改动完成后运行：

```bash
pnpm qa
```

   - 如修改 PowerShell 安装器逻辑，再追加：

```bash
pnpm test:pwsh:all
```

实现过程中未修改 PowerShell 安装器逻辑，也不新增 `-Scope` 覆盖；`pnpm test:pwsh:all` 不是本任务必需项。

## Risk Points

- 全局安装的本地 skill 可能是复制目录，不能依赖目录链接反查仓库。
- `skills.config.json` 是 JSON，新增项时必须保持逗号和排序清晰。
- `.agents/skills/repo-ops` 不能留下第二份真实副本，否则后续维护会分叉。
- 不要将该 skill 同时安装到 global 和 project scope，避免重复入口。
- 不要改 `.agents/skills/trellis-*`，本任务只处理 `repo-ops`。

## Review Gate

实现前确认：

- PRD、设计和执行计划均已覆盖用户澄清的范围。
- 用户批准开始迁移与配置修改。
