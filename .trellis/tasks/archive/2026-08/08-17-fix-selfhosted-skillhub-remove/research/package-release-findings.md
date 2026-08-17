# Package Release Findings

## Root Cause

- Internal Registry publishes `@agent-skills/cli` versions `0.1.0` and `0.1.1` only.
- Published `0.1.1 --help` does not register `remove`.
- `agent-skills/main` commit `f8fe192` already contains the complete audited `remove [skills...]` implementation and tests.
- No pending changeset references `@agent-skills/cli`, so the package version remains `0.1.1` and `changeset publish` has nothing new to publish for it.

## Existing Release Pipeline

- `.woodpecker/prepare-release-pr.yml` runs on pushes to `main` and invokes `scripts/prepare-release-pr.mjs`.
- The script runs `changeset status`, then unfiltered `changeset version`, and creates or refreshes `release/changesets` when any package is pending.
- `.woodpecker/release.yml` runs on pushes to `main`; after verification it runs `changeset publish` against the internal Forgejo npm Registry.

## Pending Batch Risk

- Current pending changesets resolve to an `@agent-skills/astro-content-studio` major release.
- Adding a CLI changeset and using the default release-PR path would aggregate the CLI patch with that unrelated major release.

## Verified Isolation Mechanism

Changesets CLI version: `2.31.1`.

Official CLI documentation exposes:

```bash
changeset version --ignore PACKAGE_NAME
```

A disposable clone of the current repository was given a patch changeset for `@agent-skills/cli`, then executed:

```bash
pnpm exec changeset version --ignore @agent-skills/astro-content-studio
```

Observed result:

- `packages/cli/package.json` changed from `0.1.1` to `0.1.2`.
- `packages/cli/CHANGELOG.md` was created with only the CLI patch summary.
- The CLI changeset was consumed.
- All Astro Content Studio changesets remained in `changeset status`.
- No Astro package version file changed.

Changesets documents that ignored packages cannot share a changeset or required dependency release with non-ignored packages. The current CLI patch is independent, so the restriction does not block this release.

## Repository Safety

- `agent-skills` currently has an unrelated modified `README.md`; release staging must exclude it.
- Parent `agent-hub` submodule gitlink must not be updated by default.
- `selfhosted.sh` correctly forwards all arguments and requires no behavior change.
- Real global skill deletion is not authorized; post-publish verification is limited to help, dry-run, and cancellation before confirmation.
