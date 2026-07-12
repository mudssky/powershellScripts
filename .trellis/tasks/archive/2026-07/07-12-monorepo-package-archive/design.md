# Monorepo package 归档设计

## 边界

本任务复用现有 `project-archive` 工具和 `archive/index.json` 索引，不引入新的归档系统。通用 package 门禁写入 `.trellis/spec/infra/repository-archive.md`，`json-diff-tool` 作为首个实践对象。

## 归档资格

package 只有在以下条件全部满足时才可进入冷归档：

1. 用户可见功能已停用、已被替代或明确不再需要。
2. 没有活动包、脚本、CI、安装或发布入口依赖它。
3. 若有兼容入口，其已迁移、明确下线或与 package 一并归档。
4. 归档后不再被 workspace、lockfile、Turbo/Vitest/QA、Dependabot、IDE 或活动规范发现。
5. 恢复时能还原原路径、引用和质量门禁。

## 实例对象

Batch 10 使用相同原因和替代说明归档三个对象：

| 源路径 | 归档路径 |
| --- | --- |
| `projects/clis/json-diff-tool` | `archive/projects/clis/json-diff-tool` |
| `scripts/pwsh/misc/Compare-JsonFiles.ps1` | `archive/scripts/pwsh/misc/Compare-JsonFiles.ps1` |
| `.trellis/spec/json-diff-tool` | `archive/.trellis/spec/json-diff-tool` |

原因为“JSON 对比工具已停止使用且无活动依赖”，替代说明为“功能已停用，仅供历史参考”。

## 活动区清理

- 从 `CLAUDE.md` 移除 package 目录与 QA 说明，不修改历史任务文档。
- 从 `powershellScripts.code-workspace` 移除 package folder。
- 从 `docs/scripts-index.md` 移除已归档的 PowerShell 脚本条目。
- 从 `pnpm-lock.yaml` 移除 package importer，并确认其专属依赖节点不再被其他 importer 需要。
- `pnpm-workspace.yaml` 使用 `projects/**`，package 移入 `archive/` 后会自动退出 workspace，无需增加单包排除规则。

## 执行与提交边界

1. 先清理活动引用，再以已审阅参数运行 `archive --execute`。
2. 归档工具使用 `git mv` 并向当前 `archive/index.json` 追加 Batch 10；执行时保留该文件中并行任务的现有改动。
3. 同一归档提交不改写被移动文件的正文，以便 Git 识别 rename 并保留历史。
4. 本任务的规范、活动引用清理和归档移动可作为一个 Conventional Commit，但不吸收当前 `psutils` 或其他并行任务改动。

## 验证与回滚

- 运行 `project-archive check`，确认索引和镜像路径一致。
- 检查 `pnpm list -r --depth -1`，确认 package 不再被 workspace 发现。
- 搜索活动树，确认只有归档内容和历史记录仍提及该工具。
- 运行根目录 `pnpm qa`；因涉及 PowerShell 脚本归档，提交前运行 `pnpm test:pwsh:all`。
- 回滚时对 Batch 10 三项执行反向 `git mv`，删除对应索引条目，恢复活动引用和 lockfile，然后重跑归档检查与质量门禁。
