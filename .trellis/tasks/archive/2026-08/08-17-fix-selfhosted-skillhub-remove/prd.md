# 修复 selfhosted skillhub remove 兼容

## Goal

让 `shell/shared.d/selfhosted.sh` 暴露的 `skillhub remove -g` 可正常进入 SkillHub 的受审计删除流程，并把本次暴露出的 package 发布门禁沉淀到 project-local `skillhub-maintainer`，避免“源码已有命令、npm 包仍是旧版本”再次发生。

## Confirmed Facts

- `selfhosted.sh` 已原样透传所有参数，函数本身没有吞掉或改写 `remove -g`。
- 任务开始时内网 Forgejo npm Registry 只有 `@agent-skills/cli@0.1.0`、`0.1.1`；`0.1.1 --help` 不包含 `remove`。
- 当前 `skills/packages/cli/src/commands.ts` 已实现 `remove [skills...]`，同时包含候选审计、交互选择、`--dry-run`、plan、receipt 和 inventory 更新。
- 直接把 `remove` 永久改为透传 `npx skills@latest remove` 会绕开上述 SkillHub 安全与状态管理语义，只能作为临时兼容方案，不能视为等价修复。
- 用户选择通过发布新版 `@agent-skills/cli` 修复根因，不添加降低审计能力的 Shell fallback。
- 当前 CLI `remove` 实现已提交到 `agent-skills/main`，但没有对应 `@agent-skills/cli` changeset，因此自动发布流程不会提升 CLI 版本。
- 仓库同时存在多项 `@agent-skills/astro-content-studio` 待发布 changeset；默认 `changeset version` 会把全部 pending release 聚合进同一个 release PR，不能把它误报成 CLI 独立发布。
- `skillhub-maintainer` 当前只覆盖 registry、发布目录和 CLI 使用，没有说明 package changeset、聚合 release PR、npm 发布验证与待发布批次风险。
- Woodpecker `#57` 的 `release/verify` 在 `git diff --exit-code -- .claude-plugin registry/generated` 失败：`registry/generated/registry.normalized.json` 尚未同步已提交的 `agent-config-manager` description，发布步骤因此安全跳过。
- Woodpecker `#57` 的 `prepare-release-pr` 在推送 `refs/heads/release/changesets` 时被 Forgejo 拒绝为 `refname conflict`；仓库已有长期 `release` 分支，Git 不允许同时存在 `release` 与其子引用 `release/changesets`。
- 在干净隔离 worktree 复现到第三个 CI 阻塞：`.woodpecker/release.yml` 使用 `pnpm install --ignore-scripts` 后只预构建 CLI，随后 `pnpm verify:ci` 先执行全 workspace typecheck；`astro-content-studio-template` 通过 workspace export 导入 `@agent-skills/astro-content-studio/integration`，但该包的 `dist/integration.js` 尚未生成，因此 `astro check` 以 `Cannot find module` 失败。
- 两个独立 Woodpecker repository secret 已恢复：`forgejo_release_token` 与 `npm_publish_token`，均仅允许 `push` 事件；当前阻塞已从缺失凭据收敛为上述仓库内容问题。
- Woodpecker `#59` 证明 prepare-release-pr、verify、materialize 和 pack 已修复，但发布容器分别缺少内网 DNS 与 Corepack；`#61` 进一步证明 Changesets 临时 clone 的 lockfile 更新会触发无关 postinstall。最终 workflow 使用 YAML anchors 统一 DNS/Corepack 配置，publish npm 显式启用 Corepack，release lifecycle 同时设置 npm/pnpm `ignore_scripts`。
- `@agent-skills/cli@0.1.2` 成功发布且包含 `remove`，但 `src/cli.ts` 的旧硬编码使 `--version` 错报 `0.1.1`。由于 npm 版本不可变，用户批准 CLI-only `0.1.3`；最终版本从 package manifest 单一读取，并补充防漂移测试。
- Woodpecker `#64` 的 prepare-release-pr、verify、materialize-and-smoke、pack-smoke、publish-git-release、publish-npm-packages 全部成功。Registry、clean explicit/latest npx、Bash/Zsh wrapper 均报告 `0.1.3`。

## Requirements

- `skillhub remove -g` 不再返回 `unknown command 'remove'`。
- 保留 Bash/Zsh 兼容和现有 public/scoped Registry 分流。
- 不降低 SkillHub `remove` 已实现的审计、确认、receipt 与 inventory 语义。
- 不在 `selfhosted.sh` 内复制复杂的版本比较、候选发现或删除逻辑。
- 在 `.agents/skills/skillhub-maintainer` 增加 package 发布流程：changeset 检查、聚合批次审计、release PR 边界、发布后 Registry 与 clean `npx` smoke。
- package 发布的领域门禁归 `skillhub-maintainer`；commit、push、PR 的通用机械流程继续归 `git-workflow`，不在两个 skill 中重复。
- 修复发布流水线的已证实阻塞：同步 registry generated artifact；迁移 Changesets PR 分支；预构建 workspace export；为发布容器补齐共享 DNS/Corepack；禁用 Changesets 临时安装的 lifecycle scripts；消除 CLI 运行时版本硬编码。
- 保留完整 verify、release-tree smoke 与 pack smoke；不得绕过失败门禁直接 publish。

## Acceptance Criteria

- [x] 通过 `selfhosted.sh` 调用 `skillhub remove -g --dry-run` 能进入 `remove` 命令解析，不执行真实删除。
- [x] `skillhub --help` 显示 `remove [skills...]`。
- [x] `bash -n shell/shared.d/selfhosted.sh` 与 `zsh -n shell/shared.d/selfhosted.sh` 通过；该文件无内容修改。
- [x] 未执行未经用户单独授权的真实全局 skill 删除；真实 `git-workflow` 候选仅输出 dry-run 计划，安装目录仍存在。
- [x] `skillhub-maintainer` 能指导 agent 检查 changeset、manifest、运行时版本源与 Registry，而不是修改 wrapper 掩盖差异。
- [x] 发布前列出完整 pending 批次；Astro Content Studio major 已显式隔离并保持待发布。
- [x] 使用空 npm 配置和临时 cache 查询 Registry，并通过已发布包的 `--version`、`--help` 与 wrapper `remove -g --dry-run` smoke。
- [x] 修改后的 project-local skill 通过 quick validation。
- [x] `prepare-release-pr` 使用 `changesets-release`，相关测试覆盖无 changeset、创建/复用 release PR、source-tip gate。
- [x] Registry generator 重跑零差异，Woodpecker release verify 通过。
- [x] clean `--ignore-scripts` 环境在 workspace typecheck 前生成 Astro dist，template typecheck 0 errors。
- [x] Woodpecker `#64` 完成 Git/npm publish；Astro Changesets PR 被维护但未合并、未发布。

## Out of Scope

- 不以 `npx skills@latest remove` 永久替代 SkillHub 的 registry-aware remove。
- 不改变其他 `skillhub` 子命令、Registry 地址或安装范围。
- 不合并或发布 Astro Content Studio 的聚合 Changesets release PR。

## Key Decisions

- 初始通过发布 `@agent-skills/cli@0.1.2` 修复 `remove`，不修改 `selfhosted.sh` 的命令分派；发布后发现不可覆盖的运行时版本硬编码，用户批准 CLI-only `0.1.3` 修复。
- 把 package release 流程纳入 project-local `.agents/skills/skillhub-maintainer`，新增按需 reference；不把仓库发布流程塞进面向日常使用的 `skillhub-cli`。
- CLI patch 与 `@agent-skills/astro-content-studio` 的 pending major release 隔离。两次使用 Changesets 2.31.1 的 `changeset version --ignore @agent-skills/astro-content-studio`，只消费 CLI changeset；最终 CLI 为 `0.1.3`，全部 Astro changesets 保留。
- 发布过程不得暂存 `skills/README.md` 的既有未提交修改，也不默认更新父仓 `skills` submodule gitlink。
- 真实 `skillhub remove -g` 删除不在本任务授权范围；只允许 `--help`、`--dry-run` 和在交互选择前取消的无破坏性 smoke。
- 2026-08-17：用户先确认只发布 CLI `0.1.2`；发现该不可变版本的 `--version` 错报后，再明确批准只发布 CLI `0.1.3`，仍不发布 Astro Content Studio。
- Changesets release PR 分支改为 `changesets-release`；同步修改脚本默认值、测试和 README 中该分支名。`skills/README.md` 的既有用户改动必须原样保留，仅单独暂存本任务位于发布流程段落的 hunk。
- `registry/generated/registry.normalized.json` 的既有漂移作为 CI 解阻提交单独同步；不改 `agent-config-manager` 源定义。
- Release verify 只在 `pnpm verify:ci` 前增加 `pnpm --filter @agent-skills/astro-content-studio build`。不重排根 `verify:ci`、不消费 Astro changeset、不修改 Astro 版本；该预构建仅满足 template 的 workspace export 前置条件。
- Woodpecker 公共 DNS 与 Corepack mirror 使用 YAML anchors/aliases 在 workflow 内单点定义；secret 保持 step-local。
- CLI program 构造器直接读取 `packages/cli/package.json`，入口不再维护版本字面量；release Phase B 测试从 manifest 推导下一 patch 与 fake Registry 基线。
