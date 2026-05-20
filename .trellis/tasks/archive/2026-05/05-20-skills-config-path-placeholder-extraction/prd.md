# skills config path placeholder extraction

## Goal

把多个脚本重复出现的配置路径解析和环境变量 placeholder 展开能力抽成通用基础设施，供后续 `Install-Skills.ps1`、GitHub CLI 安装器等脚本复用。

## Requirements

* 评估并设计通用 API，覆盖 `~`、相对 base path、`${VAR}`、`%VAR%` 这类配置路径展开场景。
* API 必须只表达通用路径/env 解析语义，不包含 skills、GitHub release、rclone 等领域概念。
* 缺失环境变量时必须有明确错误，避免路径静默落到错误目录。
* 需要明确哪些脚本先接入，避免一次性批量改动过大。

## Acceptance Criteria

* [ ] 有独立 `design.md` 和 `implement.md` 描述 API、调用方迁移顺序和验证命令。
* [ ] 通用 helper 有 Pester 测试覆盖 `~`、相对路径、`${VAR}`、缺失 env。
* [ ] 首个调用方接入后行为不变。
* [ ] 不和 config object helper 或 skills 私有模块拆分混在同一提交。

## Out of Scope

* 安装计划、agent 目录、ctx7 检测。
* 大规模替换所有历史脚本。
