# fix: 修复 rclone vitest 空测试套件

## Goal

修复 GitHub Actions Ubuntu 环境下根 Vitest 扫描 `config/service/oss/rclone/rclone-ops.test.mjs` 时报告 `No test suite found` 的问题，让该文件里的测试能被 Vitest 正确注册和执行。

## What I already know

* CI 报错文件是 `config/service/oss/rclone/rclone-ops.test.mjs`。
* 该文件命名符合 Vitest 默认测试发现模式 `*.test.mjs`。
* 文件当前从 `node:test` 导入 `describe` / `it`，而根 GitHub Action 使用 `pnpm exec vitest run` 执行。
* Vitest 官方文档说明可用 `include` / `exclude` 控制测试发现；本问题更适合修复测试 API 导入，而不是隐藏该测试文件。

## Requirements

* `rclone-ops.test.mjs` 必须使用 Vitest 注册测试套件。
* 保留现有断言逻辑和覆盖范围。
* 不修改业务脚本行为。

## Acceptance Criteria

* [x] `pnpm exec vitest run config/service/oss/rclone/rclone-ops.test.mjs` 通过。
* [x] 根目录 `pnpm qa` 通过，或明确说明无法执行的原因。

## Technical Notes

* Context7 Vitest docs: 测试文件发现可通过 `include` / `exclude` 配置，但当前文件确实是测试文件，应使用 Vitest API。
* `rclone-ops.mjs` 保留 shebang 与可执行位；通过 `.gitattributes` 固定该脚本 LF，避免 Windows checkout 后 Vitest/Vite 导入 CRLF shebang 文件时报语法错误。
* 相关文件：`config/service/oss/rclone/rclone-ops.test.mjs`。

## Verification

* `node --check config/service/oss/rclone/rclone-ops.mjs` 通过。
* `node --check config/service/oss/rclone/rclone-ops.test.mjs` 通过。
* `pnpm exec vitest run config/service/oss/rclone/rclone-ops.test.mjs --reporter=verbose --no-color` 通过，8 个测试全部通过。
* `pnpm qa` 通过；当前 Windows 环境按项目脚本跳过 Linux-only QA。

## Out of Scope

* 不调整 GitHub Actions workflow。
* 不重构 rclone 运维脚本。
