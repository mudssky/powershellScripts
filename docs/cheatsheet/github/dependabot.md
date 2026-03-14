这是一份适用于 2026 年的 Dependabot 配置速查表（Cheatsheet）。包含了你需要的 **Node.js (pnpm monorepo)**、**GitHub Actions** 以及最新的 **Python (uv)** 配置案例。

这份配置使用了最新的 **`directories`（通配符支持）** 和 **`groups`（分组更新）** 功能，旨在减少 PR 噪音。

### 📌 本仓库当前实际策略（2026-03-14）

下面的 `Copy & Paste` 示例仍然是通用模板，不等于这个仓库的真实目录布局。当前仓库实际使用的是分层维护策略：

- **GitHub Actions**：`weekly`，`monday 09:00 Asia/Shanghai`，单独分组为 `actions`
- **主 pnpm monorepo**：`monthly 09:00 Asia/Shanghai`，扫描 `/`、`/projects/**`、`/scripts/node`，将 minor/patch 按依赖名合并，major 更新冷却 60 天
- **`config/software/mpv/mpv_scripts`**：`quarterly 09:00 Asia/Shanghai`，作为独立项目单独维护；该目录当前同时存在 `pnpm-lock.yaml` 与 `package-lock.json`，首次 PR 需要确认 Dependabot 的实际 lockfile 变更范围

如果你是在维护这个仓库本身，优先以 [`.github/dependabot.yml`](../../../.github/dependabot.yml) 为准，不要直接照抄下方 `/packages/*`、`/apps/*` 示例路径。

### 🚀 核心 Cheatsheet (Copy & Paste)

文件路径: `.github/dependabot.yml`

```yaml
version: 2
updates:
  # -------------------------------------------------------
  # 1. GitHub Actions (自动更新 CI/CD 脚本)
  # -------------------------------------------------------
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      # 将所有 Actions 更新合并为一个 PR
      actions:
        patterns:
          - "*"

  # -------------------------------------------------------
  # 2. Node.js (支持 pnpm / npm / yarn Monorepo)
  # -------------------------------------------------------
  - package-ecosystem: "npm"
    # 使用 directories + 通配符一次性匹配所有包 (2024+ 新特性)
    directories:
      - "/"                # 根目录
      - "/packages/*"      # packages 下的所有子目录
      - "/apps/*"          # apps 下的所有子目录
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Asia/Shanghai"
    # 分组策略：大幅减少 PR 数量
    groups:
      # 策略A: 所有非破坏性更新(minor/patch)合为一个 PR
      non-breaking:
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"
      # 策略B: 也可以按功能分组 (可选)
      linting:
        patterns:
          - "eslint*"
          - "prettier*"

  # -------------------------------------------------------
  # 3. Python (使用 uv 包管理器) - 🆕 新特性
  # -------------------------------------------------------
  - package-ecosystem: "uv"  # 注意：专门针对 uv 的生态系统标识
    directory: "/"           # 指向包含 pyproject.toml / uv.lock 的目录
    schedule:
      interval: "weekly"
    # 同样可以使用分组
    groups:
      python-dependencies:
        patterns:
          - "*"
    # 如果 uv.lock 和 pyproject.toml 不在同一目录，需分别指定
    # 但通常 uv 项目结构都在根目录，上面配置即可
```

---

### 🔍 关键配置项详解

#### 1. Python (uv) 特别说明

GitHub Dependabot 在近期（2025年左右）增加了对 `uv` 的原生支持。

* **ecosystem**: 必须填 `"uv"`，而不是 `"pip"`。
* **文件识别**: 它会自动识别 `pyproject.toml` 和 `uv.lock`。
* **优势**: 相比传统的 pip，Dependabot 使用 uv 解析依赖速度更快，且能正确处理 uv 的 lockfile 格式。

#### 2. `groups` (分组更新) - 必用功能

这是防止 Dependabot 刷屏的神器。

* **`patterns: ["*"]`**: 最暴力的分组，把该生态系统下的**所有**更新合并到一个 PR 里。
* **`update-types`**: 可以配合使用，例如“只合并 patch 和 minor 版本”，保留 major 版本（破坏性更新）单独提 PR 以便人工审核。

#### 3. `directories` (多目录/通配符)

以前需要为每个子目录写一段配置，现在支持 glob 模式。

* **写法**: `directories: ["/packages/*"]`
* **作用**: 自动扫描 `packages` 目录下的一级子文件夹，寻找 `package.json`。

> **Repo note:** 当前仓库的 workspace 实际路径是 `/projects/**` 与 `/scripts/node`；`config/software/mpv/mpv_scripts` 不属于 root workspace，而是单独配置了一个更新器。

#### 4. `open-pull-requests-limit`

默认限制是 5 个 PR。如果你使用了分组功能，这个限制通常够用。如果没有分组，Monorepo 很容易爆满，建议显式设置：

```yaml
open-pull-requests-limit: 10
```

### 💡 常用 `ignore` 规则示例 (适用于所有生态)

如果你想忽略某些特定包的升级（例如不想升级到 React 19 或某个有 Bug 的版本）：

```yaml
    ignore:
      # 忽略 React 的主版本更新 (如 18 -> 19)
      - dependency-name: "react"
        update-types: ["version-update:semver-major"]
      
      # 完全忽略某个包
      - dependency-name: "problematic-package"
```
