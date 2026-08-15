# 统一 Shell 配置注释规范实施计划

## 实施前检查

- [ ] 确认活动任务仍为 `.trellis/tasks/08-15-shell-comment-convention`。
- [ ] 重新读取 `prd.md`、`design.md` 和本文件。
- [ ] 读取 `.trellis/spec/shell-shared/package/index.md` 与目标文件最新内容。
- [ ] 重新枚举 `shell/deploy.sh`、`shell/shared.d/*.sh`、`shell/bash.d/*.sh`、`shell/zsh.d/*.zsh`，确认没有新增或删除的活跃文件。
- [ ] 在仓库外保存全部目标文件的实施前快照；单独确认 `shell/shared.d/node.sh` 当前未提交功能改动仍在。

## 实施步骤

1. 新增 `.trellis/spec/shell-shared/package/comment-conventions.md`，写入四层模板、函数分级条件、字段语义、反模式和审查清单。
2. 更新 `.trellis/spec/shell-shared/package/index.md`：在 Pre-Development Checklist 与 Quality Check 中链接注释规范，不复制完整模板。
3. 迁移 `shell/deploy.sh`：统一文件头、配置/帮助/日志/功能/主逻辑章节与全部函数契约。
4. 迁移 `shell/shared.d/*.sh`：
   - 补齐或统一文件头。
   - 用单行横向标题划分工具或配置主题。
   - 将所有函数改为紧凑或完整契约。
   - 清理“关键修改”、编号步骤、英文占位标题和旧字段名。
   - 将 `node.sh` 的两个 pnpm 条件块归入同一个 `pnpm` 标题，保持功能代码逐行不变。
5. 迁移 `shell/bash.d/*.sh` 与 `shell/zsh.d/*.zsh`：统一文件头、配置章节与嵌套函数契约；注释缩进跟随所属条件块。
6. 全范围审查：确认没有修改范围外文件，没有把单个命令过度拆成章节，没有为简单函数误用完整块。

## 验证

1. 对比实施前快照与当前文件：忽略完整行注释和空白行后，所有目标文件内容必须一致；若不一致，定位并回退误改。
2. 检查目标范围内的旧格式：
   - 旧式 `# ===== 标题 =====`、`# --- 标题 ---` 与三行章节块。
   - `参数:`、`入参:`、`返回:`、`返回值:`、`设计意图:` 等半角字段。
   - “关键修改”、临时编号步骤和纯语法复述。
3. 对 `shell/deploy.sh`、`shell/shared.d/*.sh`、`shell/bash.d/*.sh` 运行 Bash 语法检查。
4. 对 `shell/zsh.d/*.zsh` 运行 Zsh 语法检查。
5. 阅读最终 diff，确认 `shell/shared.d/node.sh` 的 pnpm 功能改动完整保留，且本任务只新增或修改注释与空行。
6. 纯文案/注释改动按仓库规则无需运行 `pnpm qa`、`pnpm test:bash` 或 PowerShell 测试；若实施中出现任何可执行行变化，停止并修复，不以扩大测试替代行为保持要求。

## 风险文件与回滚点

- `shell/shared.d/node.sh`：包含用户未提交功能改动。禁止整文件 checkout、reset 或覆盖写入。
- `shell/deploy.sh`、`shell/shared.d/proxy.sh`、`shell/shared.d/claude-profile.sh`：函数和章节密集，最容易在批量编辑时误伤续行或重定向。
- `shell/bash.d/fzf-history.sh`、`shell/zsh.d/fzf-history.zsh`：函数位于条件块内，必须保持注释与代码缩进一致。
- 回滚只针对本任务注释 hunk；使用实施前快照核对，不回退用户原有工作。

## 启动前门禁

- [ ] `prd.md` 无阻塞问题且已完成收敛重写。
- [ ] `design.md` 与 `implement.md` 已覆盖范围、模板、验证和回滚。
- [ ] `implement.jsonl` 与 `check.jsonl` 各包含至少一条真实规范上下文。
- [ ] 用户已在最终规划摘要之后明确批准实施。
