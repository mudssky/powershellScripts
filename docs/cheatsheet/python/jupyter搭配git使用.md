这份文档整合了**目录分离（Directory Splitting）**策略，实现了 Git 仓库的整洁与高效管理。这是目前 Jupyter Notebook 工程化管理的**终极最佳实践**。

---

# Git + Jupyter Notebook (Python/Deno) 最佳实践指南 v2.0
>
> **核心理念：UI 与逻辑分离**
>
> * **Notebooks (`.ipynb`)**：作为交互界面、草稿本和可视化展示，统一收纳在独立目录。
> * **Scripts (`.py` / `.ts`)**：作为逻辑核心，自动同步生成，用于 Git 版本控制、Code Review 和 CI/CD。

---

## 1. 理想的项目结构

采用**平行目录结构**，保持 `notebooks/` 和 `src/` (或 `scripts/`) 的层级镜像。

```text
my-project/
├── .gitignore
├── jupytext.toml          # 核心配置文件
├── pyproject.toml         # (Python 项目配置)
├── deno.json              # (Deno 项目配置 & Import Maps)
├── notebooks/             # 【编辑区】在这里写代码、画图
│   ├── analysis.ipynb
│   └── experiments/
│       └── deep_dive.ipynb
└── notebook_src/                   # 【仓库区】自动生成的纯代码，用于提交
    ├── analysis.py        # (或 .ts)
    └── experiments/
        └── deep_dive.py   # (或 .ts)
```

---

## 2. 环境准备

无论使用 Python 还是 Deno Kernel，都需要 Python 环境来运行 Jupytext 工具。

```bash
# 1. 安装核心同步工具
pip install jupytext

# 2. (可选) 安装清理工具 - 如果你决定要在 Git 中提交 .ipynb
pip install nbstripout
```

---

## 3. 核心配置：Jupytext (自动分流)

在项目根目录新建 `jupytext.toml`。使用 `///` 语法实现目录映射。

### 场景 A：Python 项目

```toml
# jupytext.toml
# 将 notebooks/ 目录下的 .ipynb 映射到 notebook_src/ 目录下的 .py
# 格式使用 "py:percent" (兼容各种 IDE 的标准脚本格式)
default_jupytext_formats = "notebooks///ipynb,notebook_src///py:percent"
```

### 场景 B：Deno (TypeScript) 项目

```toml
# jupytext.toml
# 将 notebooks/ 目录下的 .ipynb 映射到 notebook_src/ 目录下的 .ts
default_jupytext_formats = "notebooks///ipynb,notebook_src///ts:percent"
```

> **生效方式**：配置完成后，每当你保存 `notebooks/test.ipynb`，Jupytext 会自动创建/更新 `notebook_src/test.py` (或 `.ts`)。

---

## 4. 解决 Import 路径难题 (关键步骤)

由于文件被分开了，**相对路径 (`../utils`) 极易失效**。必须使用**绝对路径映射**。

### Python 方案：Editable Install

将项目本身视为一个包。

1. 在根目录确保有 `setup.py` 或 `pyproject.toml`。
2. 以开发者模式安装：

    ```bash
    pip install -e .
    ```

3. **在 Notebook 中引用**：

    ```python
    # 不要用 from ..src import utils
    # 使用绝对包名 (无论 notebook 在哪一层都有效)
    from my_project.utils import helper
    ```

### Deno 方案：Import Maps

利用 `deno.json` 定义路径别名。

1. 编辑根目录 `deno.json`：

    ```json
    {
      "imports": {
        "@/": "./src/"
      }
    }
    ```

2. **在 Notebook 中引用**：

    ```typescript
    // 无论文件被同步到哪里，@/ 永远指向 src/
    import { helper } from "@/utils.ts";
    ```

---

## 5. Git 策略配置 (.gitignore)

根据团队需求，有两种流派：

### 流派一：代码纯净派 (推荐)

**只提交生成的脚本，完全忽略 Notebook。**

* **优点**：仓库极小，Diff 完美，彻底杜绝冲突。
* **缺点**：GitHub 上无法直接预览图表（需拉取代码后在本地运行）。

```text
# .gitignore
# 忽略所有 notebook
notebooks/*.ipynb
notebooks/**/*.ipynb
.ipynb_checkpoints/

# 确保 notebook_src 被追踪
!notebook_src/
```

### 流派二：图表保留派

**同时提交脚本和 Notebook（但清除 Notebook 的元数据）。**

* **优点**：GitHub 可预览 Notebook 内容。
* **工具**：必须配置 `nbstripout` 防止冲突。

```text
# .gitignore
.ipynb_checkpoints/
```

**配置自动化清理 (pre-commit)**：
在根目录 `.pre-commit-config.yaml`：

```yaml
repos:
-   repo: https://github.com/kynan/nbstripout
    rev: 0.6.1
    hooks:
    -   id: nbstripout
        # 仅针对 notebooks 目录下的文件
        files: ^notebooks/
```

**方案三：Node.js 生态整合 (Husky + lint-staged)**

适用于前端/Deno 项目，利用 `package.json` 统一管理指令与 Hooks。

1. **package.json scripts**

   方便手动运行同步或检查：
1. nb:sync 用于双向同步，比较时间戳，更新旧的一方
2. nb:check-sync 一致性检查（不修改文件），忽略元数据检查notebook和py文件是否匹配
3. nb:hydrate 用于将 notebook_src 中的脚本同步回 notebooks 目录，保留元数据，适用于初次git clone ，只有py文件的情况

可以在项目中创建 `.lab-config/overrides.json` 来固化jupyter lab配置

   ```json
   {
     "scripts": {
       "nb:clean": "nbstripout notebooks/**/*.ipynb",
       "nb:sync": "jupytext --sync notebooks/**/*.ipynb",
       "nb:check-sync": "jupytext --check notebooks/**/*.ipynb",
       "nb:hydrate": "jupytext --sync src/**/*.py",
       "lab": "uv run --env JUPYTERLAB_SETTINGS_DIR=./lab-config jupyter lab",
       "lab:remote": "uv run --env JUPYTERLAB_SETTINGS_DIR=./.lab-config jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root",
       "lab:clean": "uv run jupyter lab clean",
     }
   }
   ```

4. **配置 lint-staged**

   实现提交时自动同步脚本，确保 `ipynb` 与 `src` 代码一致。如果需要保留 Notebook 但清除输出（流派二），可增加 `nbstripout`。

   ```json
   // package.json
   {
     "lint-staged": {
       "notebooks/**/*.ipynb": [
         "nbstripout",
         "jupytext --sync",
         // 自动将生成的脚本文件加入本次提交
         "git add notebook_src/"
       ]
     }
   }
   ```

---

## 6. 开发工作流总结

1. **打开编辑器**：
    * 在 VS Code / Jupyter Lab 中打开 `notebooks/xxx.ipynb`。
2. **编写与运行**：
    * 像平常一样交互式运行代码、查看图表。
    * 使用 `import` 导入模块时，使用配置好的绝对路径（Python包名 或 Deno `@/`）。
3. **保存**：
    * 按下 `Ctrl+S`。
    * **Jupytext 自动触发**：瞬间更新 `notebook_src/xxx.py` (或 `.ts`)。
4. **提交 Git**：
    * `git status` 会显示 `notebook_src/xxx.py` 有变更。
    * `git diff` 查看清晰的代码改动。
    * `git add notebook_src/` (如果采用流派二，同时也 add notebooks/)。
    * `git commit`。

## 7. 常见问题 (FAQ)

* **Q: 我已有现存的 .ipynb，如何应用此结构？**
  * **A**: 将 ipynb 移动到 `notebooks/` 文件夹，运行一次 `jupytext --sync notebooks/my_old.ipynb`，它会根据配置文件在 `notebook_src/` 生成对应的脚本。
* **Q: 团队里其他人没有装 Jupytext 怎么办？**
  * **A**: 如果他们只修改 `notebook_src/` 下的代码，没问题。如果他们修改 `notebooks/` 下的 ipynb 且保存了，但没有生成新的脚本，Git 就只会记录旧脚本。
  * **强制措施**：在 CI (GitHub Actions) 中运行检查，或者使用 pre-commit hook 强制检查同步状态（`jupytext --check notebooks/`）。
