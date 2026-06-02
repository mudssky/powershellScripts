# Node/Vitest Scripts Spec

> 本规范记录根目录 Vitest 会发现的 Node 脚本测试约定，尤其是 `config/service/**` 下的 `.mjs` 运维脚本与旁路测试文件。

---

## Scenario: Vitest 执行 Node 脚本旁路测试

### 1. Scope / Trigger

- Trigger: 修改根目录 `pnpm exec vitest run` 会发现的 `*.test.mjs` / `*.spec.mjs`，或修改这些测试直接导入的 Node `.mjs` 脚本。
- Scope: 不在独立 workspace 包内、但会被根 Vitest 扫描的配置服务脚本，例如 `config/service/oss/rclone/rclone-ops.test.mjs`。
- Design intent: 测试文件必须被 Vitest 正确注册；被测试导入的 CLI 脚本仍保留 Node 直接执行能力。

### 2. Signatures

- Vitest API import:

```js
import { describe, it, test, expect, vi } from 'vitest'
```

- Tested module import:

```js
import { parseArgs } from './script.mjs'
```

- Shebang script line-ending contract:

```gitattributes
config/service/path/to/script.mjs text eol=lf
```

### 3. Contracts

- `*.test.mjs` / `*.spec.mjs` 会被 Vitest 默认测试发现模式扫描；如果文件确实是测试，不要用 `exclude` 隐藏问题。
- 由 Vitest 运行的测试必须从 `vitest` 导入 `describe`、`it`、`test`、`expect`、`vi` 等测试 API。
- 不要在 Vitest 测试文件里从 `node:test` 导入 `describe` / `it`；Vitest 会发现文件，但不会注册这些 suite，CI 会报 `No test suite found`。
- 带 `#!/usr/bin/env node` 的 `.mjs` CLI 如果会被 Vitest/Vite 直接导入，应在 `.gitattributes` 固定为 LF，避免 Windows checkout 后 CRLF shebang 触发 Vite 解析错误。
- 如果 README 或调用方支持 `./script.mjs` 直接执行，应优先保留 shebang；不要为了测试导入方便直接删除 CLI 执行契约。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `*.test.mjs` 使用 `node:test` API | 根 Vitest 可能报 `No test suite found` |
| `*.test.mjs` 使用 `vitest` API | Vitest 能注册并执行 suite/test |
| 被导入 `.mjs` 含 LF shebang | Node 与 Vitest/Vite 都能解析 |
| 被导入 `.mjs` 含 CRLF shebang | Vitest/Vite 可能报 `SyntaxError: Invalid or unexpected token` |
| 脚本仍需直接执行 | 保留 shebang，并用 `.gitattributes` 固定 LF |
| 脚本只通过 `node script.mjs` 调用且无直接执行需求 | 可移除 shebang，但需同步 README/调用方契约 |

### 5. Good/Base/Bad Cases

- Good: 测试文件从 `vitest` 导入测试 API，源脚本保留 shebang，`.gitattributes` 对该脚本声明 `text eol=lf`。
- Base: 源脚本不含 shebang，测试直接导入普通 ESM 模块。
- Bad: 测试文件使用 `node:test`，但 CI 入口是 `vitest run`。
- Bad: 为绕过 CRLF shebang 解析问题删除 shebang，却没有确认脚本是否仍需要直接执行。

### 6. Tests Required

- Syntax check: `node --check <script.mjs>` 与 `node --check <test.mjs>`。
- Targeted Vitest: `pnpm exec vitest run <test.mjs> --reporter=verbose --no-color`。
- Project gate: 根目录 `pnpm qa`；如果当前平台跳过 Linux-only QA，需要在任务记录里说明。
- Line-ending check: `git ls-files --eol -- <script.mjs> .gitattributes`，确认带 shebang 的被测脚本工作区为 `w/lf`。

### 7. Wrong vs Correct

#### Wrong

```js
import { describe, it } from 'node:test'

describe('script behavior', () => {
  it('works', () => {})
})
```

问题：文件名会被 Vitest 发现，但 suite 注册到了 Node 内置测试运行器，Vitest 看不到测试套件。

#### Correct

```js
import { describe, it } from 'vitest'

describe('script behavior', () => {
  it('works', () => {})
})
```

理由：测试 API 与运行器一致，CI 的 `vitest run` 能正确统计 suite/test。

#### Shebang line endings

```gitattributes
.gitattributes text eol=lf
config/service/oss/rclone/rclone-ops.mjs text eol=lf
```

理由：保留 `#!/usr/bin/env node` 的 CLI 能力，同时避免 Windows checkout 后 CRLF shebang 被 Vite 导入解析失败。
