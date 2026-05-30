# 安装 mattpocock skills

## Goal

将 `mattpocock/skills` 纳入统一 skill 安装配置，方便通过 `ai/skills/Install-Skills.ps1` 同步安装到已配置的 agent。

## Requirements

- 在 `ai/skills/skills.config.json` 中新增 `mattpocock/skills` 的远程 GitHub skill 配置。
- 只安装对日常编码协作最有用的精选 skill，保留 `to-prd` 用于需求整理；暂不安装 `to-issues`、`triage`、写作、课程脚手架和 Claude hook 相关 skill。
- 复用现有 skills 安装器流程，不改动安装脚本执行逻辑。
- dry-run 时能够按名称筛选并展示 `mattpocock/skills` 的安装计划。

## Acceptance Criteria

- [x] `pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name mattpocock-skills -DryRun` 能成功生成安装计划。
- [x] 安装计划中包含 `mattpocock/skills` 源。
- [x] 安装计划不再使用 `--skill *`，而是列出精选 skill。
- [x] 根目录 `pnpm qa` 通过。

## Notes

- 这是轻量配置改动，PRD-only 即可。
