# Implementation Plan

## Skill Guidance

1. Run the branch gate in `agent-hub` before editing project-local skill files.
2. Update `.agents/skills/skillhub-maintainer/SKILL.md`:
   - extend the trigger description and use cases to package/CLI release work;
   - add a mandatory package-release gate to the implementation workflow;
   - route detailed commands to `references/package-release.md`;
   - keep generic Git mechanics delegated to `git-workflow`.
3. Create `.agents/skills/skillhub-maintainer/references/package-release.md` with:
   - version-drift diagnosis;
   - changeset creation and batch audit;
   - partial versioning with `--ignore` and its safety restrictions;
   - Woodpecker release flow;
   - post-publish clean npm/npx smoke;
   - immutable-version rollback guidance.
4. Validate the project-local skill with the installed skill audit entry and check all relative links.

## Isolated CLI Patch Release

1. Run the branch gate in `agent-hub/skills`; stay on `main` if the rendered trunk policy permits it.
2. Confirm the only existing uncommitted file is the unrelated `README.md` change and leave it untouched.
3. Add a patch changeset for `@agent-skills/cli` describing the audited `remove` command.
4. Run `pnpm exec changeset status`; record the CLI patch and existing Astro Content Studio major batch.
5. Run:

   ```bash
   pnpm exec changeset version --ignore @agent-skills/astro-content-studio
   ```

6. Check the resulting diff:
   - CLI version is `0.1.2`;
   - CLI changelog describes `remove`;
   - the temporary CLI changeset was consumed;
   - Astro package files are unchanged;
   - all Astro changesets remain pending;
   - unrelated `README.md` remains unstaged.
7. Run package verification:

   ```bash
   pnpm --filter @agent-skills/cli verify
   pnpm exec changeset status
   ```

8. Commit only CLI release files in the `skills` repository using the rendered Conventional Commit rules. Do not update the parent submodule gitlink.
9. Commit the `skillhub-maintainer` documentation separately in `agent-hub`, excluding unrelated task files or submodule state.
10. Push the `skills/main` release commits and follow Woodpecker until the final CLI patch is published. The initial `0.1.2` fixed `remove`; the approved immutable-version correction publishes `0.1.3`. Push the project-local skill commit according to the repository's Git workflow.

## CI Release Unblocking

1. Regenerate registry artifacts with the repository command and format the generated JSON exactly as CI does.
2. Confirm the only semantic generated change is the already-committed `agent-config-manager` description; commit only `registry/generated/registry.normalized.json` as a dedicated generated-artifact sync.
3. Change the Changesets release PR branch contract from `release/changesets` to `changesets-release` in:
   - `scripts/prepare-release-pr.mjs` default branch;
   - `scripts/prepare-release-pr.test.mjs` ref assertions;
   - the single release-workflow sentence near `skills/README.md:403`.
4. Preserve the existing unrelated README hunk around the internal npx instructions. Stage only the branch-name documentation hunk together with the script and test.
5. 在 `.woodpecker/release.yml` 的 verify step 中，于 `pnpm verify:ci` 前增加 `pnpm --filter @agent-skills/astro-content-studio build`，满足 Astro template typecheck 的 workspace export 前置条件；不修改 Astro version、changeset 或 publish step。
6. 从干净 `pnpm install --frozen-lockfile --ignore-scripts` 环境运行与 release verify 一致的前置与验证：

   ```bash
   pnpm rebuild esbuild sharp
   node scripts/bootstrap-agnix.mjs
   pnpm --filter @agent-skills/cli build
   pnpm --filter @agent-skills/astro-content-studio build
   pnpm skillhub registry schema
   pnpm exec biome format --write .claude-plugin/marketplace.json registry/generated/registry.normalized.json
   pnpm verify:ci
   node scripts/pack-public-packages.mjs
   ```

   生成物验证以“重跑 generator 前后目标 diff hash 不变”为本地未提交态门禁；提交后 Woodpecker 继续执行 `git diff --exit-code -- .claude-plugin registry/generated`。

7. 提交并推送 CI 解阻修复：generated artifact sync、release branch contract、workspace prebuild、publish container DNS/Corepack、Changesets lifecycle ignore-scripts。使用真实 push event；不创建空提交，不绕过 Woodpecker。
8. Follow both Woodpecker workflows until prepare-release-pr, verify, materialize-and-smoke, pack-smoke, publish-git-release and publish-npm-packages all succeed.
9. If an immutable published version exposes a package-internal defect, fix source, add the next CLI-only patch changeset, repeat partial versioning with Astro ignored, and re-run the full pipeline. Do not overwrite the existing version.
10. Do not merge the generated Astro release PR in this task.

## Post-Publish Smoke

1. Query the internal Registry with an empty npm config and confirm final version `0.1.3`.
2. Run clean explicit/latest `npx --version` and `--help`; confirm version/manifest agreement and `remove [skills...]`.
3. Source `/Users/mudssky/projects/powershellScripts/shell/shared.d/selfhosted.sh` in Bash and Zsh; confirm `skillhub --version` and `skillhub remove --help`.
4. Run Bash/Zsh syntax checks on `selfhosted.sh` even though no content change is expected.
5. Run an existing skill through `remove -g --dry-run --no-receipt --no-inventory`; do not confirm or execute deletion, then verify the installed directory still exists.
6. Record exact observed output and pipeline IDs.

## Completion Gate

- Published CLI version is `0.1.3`, reads its version from package manifest, and exposes `remove` through the real `selfhosted.sh` entry.
- Astro Content Studio remains unversioned and pending for its own release review.
- `selfhosted.sh` has no compatibility fallback and no diff.
- Project-local release guidance passes skill validation and records manifest/runtime/Registry, immutable-version and container gates.
- Woodpecker `#64` is fully successful across both workflows and all publish steps.
- `changesets-release` contains only the pending Astro version proposal and is not merged.
- No parent gitlink or real installed skill was modified; dry-run left `git-workflow` present.
