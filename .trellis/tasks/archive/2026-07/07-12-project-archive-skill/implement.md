# 项目冷归档技能与索引自动化实施计划

## 1. 开发前准备

- [x] 用户审阅规划并批准进入实现。
- [x] 运行 `task.py start`，加载 `trellis-before-dev` 与相关 infra/skill 规范。
- [x] 记录工作区状态，保护用户已有改动。

## 2. 初始化 skill

- [x] 使用系统 `init_skill.py` 在 `.agents/skills/` 创建 `project-archive`。
- [x] 仅保留 `SKILL.md`、`scripts/`、`tests/` 和匹配主文档的 `agents/openai.yaml`。
- [x] 编写中文 skill 流程，明确审计、确认、dry-run、执行、验证和回滚。

## 3. 实现结构化索引

- [x] 新增 `archive/index.json`，迁移当前 8 条索引记录。
- [x] 实现 JSON 读取、类型归一化、schema 校验和稳定排序。
- [x] 删除 `archive/README.md`，并迁移仍有效的活动引用。

## 4. 实现归档 CLI

- [x] 实现仓库根发现和安全路径解析。
- [x] 实现 `check`。
- [x] 实现 `plan` 的镜像目标、引用扫描和 JSON 草案输出。
- [x] 实现带 `--execute` 门禁的 `archive`，通过参数数组调用 `git mv` 并原子更新索引。
- [x] 实现稳定 stdout/stderr 和退出码。

## 5. 测试

- [x] 覆盖 schema、重复项、路径逃逸和非镜像路径。
- [x] 覆盖索引稳定排序、原子写入和重复执行保护。
- [x] 使用临时 Git 仓库覆盖 plan、archive、源目标冲突和 Git 失败。
- [x] 验证重复 check 和重复候选处理幂等。

## 6. 规范同步

- [x] 更新 `.trellis/spec/infra/repository-archive.md`，声明 JSON 唯一真源并移除 README 合同。
- [x] 更新 infra spec index 描述。
- [x] 不修改历史归档任务中的当时设计记录。

## 7. 质量门禁

- [x] 运行 `python3 .../archive_project.py --help`。
- [x] 运行 `python3 -m unittest discover -s .agents/skills/project-archive/tests -p 'test_*.py'`：11 个测试通过。
- [x] 运行 `python3 -m compileall .agents/skills/project-archive/scripts .agents/skills/project-archive/tests`。
- [x] 运行 `python3 /Users/mudssky/.agents/skills/skill-dev-guidelines/scripts/audit_skill.py .agents/skills/project-archive --strict`：0 error、0 warning。
- [x] 运行系统 `quick_validate.py .agents/skills/project-archive`：通过。
- [x] 运行当前仓库 `check`：8 条索引通过。
- [x] 运行根 `pnpm qa`：通过。

## 8. 收尾

- [x] 检查 diff、生成文件和工作区状态。
- [x] 更新任务验证结果，提交 `fe8b47b feat(repo): 新增项目冷归档技能与 JSON 索引`。
- [x] 使用 Trellis finish 流程归档任务。
