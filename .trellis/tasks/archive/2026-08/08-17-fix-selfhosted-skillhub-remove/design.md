# Design

## Boundaries

This task fixes the published-package boundary, not the shell wrapper.

- `powershellScripts/shell/shared.d/selfhosted.sh` remains unchanged. It already forwards arguments correctly and keeps public npm dependencies separate from the internal `@agent-skills` registry.
- `agent-hub/.agents/skills/skillhub-maintainer` gains repository-specific package-release guidance.
- `agent-hub/skills` versions and publishes the already-committed `remove` implementation as `@agent-skills/cli@0.1.2`.
- The parent `agent-hub` submodule gitlink is not updated unless separately requested.

## Skill Structure

Update `skillhub-maintainer/SKILL.md` only with high-frequency routing and mandatory gates:

- package/CLI release requests trigger this skill;
- source/package/registry version drift must be checked before modifying consumers;
- package release details route to `references/package-release.md`.

Add `references/package-release.md` for the low-frequency repository workflow:

1. Compare source capability, package manifest version, internal Registry version, and pending changesets.
2. Add a package-scoped changeset when committed behavior has not entered a release.
3. Run `changeset status` and list every package plus effective semver level in the pending release batch.
4. If unrelated packages must not release together, use a verified partial-version operation rather than deleting or moving their changesets.
5. Validate the versioned package locally, then use the repository's existing push-to-main release pipeline.
6. Verify the internal Registry and a clean `npx` installation after publication.

`git-workflow` continues to own generic branch, commit, push, and PR mechanics. `skillhub-maintainer` owns only domain-specific release gates and verification.

## Isolated CLI Release

The repository currently has pending `@agent-skills/astro-content-studio` changesets whose effective level is major. The CLI release must not consume them.

Create a patch changeset for `@agent-skills/cli`, then run:

```bash
pnpm exec changeset version --ignore @agent-skills/astro-content-studio
```

Changesets 2.31.1 documents `--ignore` for partial repository releases. A disposable-clone experiment confirmed this exact repository state produces:

- `packages/cli/package.json`: `0.1.1` -> `0.1.2`;
- new `packages/cli/CHANGELOG.md` containing only the CLI patch;
- all Astro Content Studio changesets remain pending;
- no Astro package version change.

After the version commit reaches `skills/main`:

- `.woodpecker/release.yml` runs `changeset publish` and publishes the newly versioned CLI;
- `.woodpecker/prepare-release-pr.yml` still sees the untouched Astro changesets and maintains their separate aggregate release PR.

## CI Release Blockers

Woodpecker `#57` 与后续 clean pipeline 逐层暴露六类独立的 publish 前阻塞：

1. `release/verify` regenerates registry artifacts and rejects drift. The committed `agent-config-manager` description already changed, but `registry/generated/registry.normalized.json` still contains the previous description. Run the existing generator and commit only its deterministic output; do not edit the generated JSON manually or change the source definition.
2. `prepare-release-pr.mjs` defaults to `release/changesets`, while the repository already owns the long-lived `release` branch for the immutable release tree. Git ref namespaces cannot contain both `refs/heads/release` and `refs/heads/release/changesets`, so Forgejo correctly rejects the push.
3. Release verify 使用 `pnpm install --ignore-scripts`，只在 `pnpm verify:ci` 前构建 CLI；template typecheck 因 Astro workspace export 的 dist 尚未生成而失败。
4. 独立 publish containers 不继承其他 step 的网络和 Corepack 状态；Git publish 需要内网 DNS，npm publish 需要内网 DNS、Corepack 和 mirror 环境。workflow 内用 YAML anchors 单点定义公共值，secret 保持 step-local。
5. Changesets 临时 clone 在 lockfile 更新时会自动运行 `pnpm install`；`runLifecycle` 必须同时设置 npm/pnpm `ignore_scripts`，避免无关 postinstall 下载阻塞 release PR。
6. CLI 入口硬编码版本导致已发布 `0.1.2` 的 `--version` 错报 `0.1.1`。版本必须从 package manifest 单一读取；不可变的 `0.1.2` 保留，用户批准 CLI-only `0.1.3` 修复。

Use `changesets-release` as the Changesets PR branch. Update the script default, its fixture assertions, and the release-workflow README sentence together. The existing unrelated README hunk remains untouched and unstaged; the release branch-name hunk is staged independently.

在 `.woodpecker/release.yml` 的 verify step 中，于 `pnpm verify:ci` 前定向运行 `pnpm --filter @agent-skills/astro-content-studio build`。这只生成被 template typecheck 消费的 workspace dist，不修改版本、不消费 changeset，也不发布 Astro。相比重排根 `verify:ci` 或提前运行全 workspace build，这个修复范围更小，并保持其他流水线的 QA 顺序不变。

所有 CI 修复与 CLI `0.1.3` version files 分批提交到 `main`。`changesets-release` 只维护未消费的 Astro aggregate release proposal，不在本任务合并；npm publication 只来自已进入 `main` 的 CLI version files。

## Verification

Before push:

- skill structure audit for `.agents/skills/skillhub-maintainer`;
- CLI package `verify` and build;
- `changeset status` confirms Astro remains pending and CLI has been consumed into `0.1.3`;
- staged diffs exclude the existing unrelated `skills/README.md` change.
- targeted `node --test scripts/prepare-release-pr.test.mjs` after changing the branch contract;
- `pnpm skillhub registry schema`, formatter for generated JSON, and zero diff after regeneration;
- 干净 `--ignore-scripts` 安装后先构建 CLI 与 Astro Content Studio workspace package，再运行 repository `pnpm verify:ci` 和 public-package pack smoke；

After publish:

- query `@agent-skills/cli` through a clean npm config and confirm `0.1.3`;
- clean explicit/latest `npx @agent-skills/cli --version` both report `0.1.3` and `--help` lists `remove [skills...]`;
- source `selfhosted.sh` in Bash/Zsh and confirm `skillhub --version` plus `skillhub remove --help`;
- run a real installed candidate through `remove -g --dry-run --no-receipt --no-inventory` and verify its directory remains present.

## Risk and Rollback

- npm package versions are immutable after publication. Before push, rollback is a normal Git revert. After publication, correction requires a new patch version such as `0.1.3`; do not unpublish or overwrite `0.1.2`.
- Merging an aggregate Changesets release PR without auditing its package list could publish the unrelated Astro major. The partial-version command and post-version status check are mandatory gates.
- Existing unrelated modifications in `skills/README.md` and other repositories must remain unstaged.
- A generated artifact commit can accidentally absorb unrelated output. Stage only `registry/generated/registry.normalized.json` after confirming its sole semantic change is the already-committed `agent-config-manager` description.
- Changing only the script branch name without tests and README would create a second contract. Update script, test assertions, and the single release-workflow documentation hunk atomically.
