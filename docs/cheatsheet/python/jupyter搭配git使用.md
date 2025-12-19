`.ipynb`（Jupyter Notebook）本质上是 **JSON** 格式的文件。直接用 Git 管理会有两大痛点：

1. **Diff 难以阅读**：JSON 结构混乱，且包含大量元数据（Execution count, metadata）。
2. **冲突难以解决**：多人修改同一个 Notebook 极易产生合并冲突，且合并后文件往往损坏（JSON 格式错误）。
3. **仓库体积膨胀**：Notebook 中的图片和输出结果（base64 编码）会使 `.git` 文件夹迅速变大。

以下是针对 Python 和 Deno (TypeScript/JavaScript) 的 **Git + ipynb 最佳实践方案**。

---

### 核心策略：三选一 (或组合)

根据团队需求，通常有三种流派：

1. **极简派 (推荐)**：只保留代码，提交前**清除所有输出**。
2. **同步派 (最佳实践)**：使用 **Jupytext** 双向同步，Git 只管理生成的 `.py` / `.ts` / `.md` 文件。
3. **保留派**：必须保留输出，但使用工具优化 Diff 和 Merge。

---

### 方案一：自动化清除输出 (nbstripout)

**适用场景**：你只需要版本控制代码，不关心运行结果。这是最通用的做法。

#### 1. 安装工具

无论你是用 Python 还是 Deno kernel，都需要 Python 环境来安装这个工具（它是目前生态最成熟的）：

```bash
pip install nbstripout
```

#### 2. 配置 Git Filter

在你的项目根目录下运行：

```bash
nbstripout --install
```

这会在 `.git/config` 中设置 filter。当你执行 `git add` 时，它会自动剔除 `.ipynb` 中的 output 和 execution count，但本地文件保持原样。

* **优点**：Git 历史极其干净，Diff 清晰。
* **缺点**：拉取代码后，Notebook 是空的（没有图表），需要重新运行。

---

### 方案二：使用 Jupytext 双向同步 (强烈推荐)

**适用场景**：需要进行 Code Review，或者希望能像普通脚本一样编辑 Notebook。这也是处理 **Deno** 的最佳方式。

**原理**：你编辑 `.ipynb`，保存时 Jupytext 自动生成一个对应的源码文件（`.py` 或 `.ts`）。你将源码文件加入 Git，而忽略（或 strip）`.ipynb`。

#### 1. 安装

```bash
pip install jupytext
```

#### 2. 配置同步 (Python)

在 Notebook 目录下：

```bash
# 将 notebook.ipynb 与 notebook.py 建立双向绑定
jupytext --set-formats ipynb,py:percent notebook.ipynb
```

此时会生成一个 `notebook.py`。

* **Git 策略**：`git add notebook.py`，并在 `.gitignore` 中忽略 `*.ipynb`（或者结合方案一提交清除输出后的 ipynb）。

#### 3. 配置同步 (Deno / TypeScript)

Deno 用户通常在 Notebook 中写 TypeScript。Jupytext 支持 TS。

```bash
# 将 notebook.ipynb 与 notebook.ts 建立双向绑定
jupytext --set-formats ipynb,ts:percent notebook.ipynb
```

生成的 `notebook.ts` 是纯文本代码，带有特殊注释（`# %%`）标记单元格。

* **优势**：
  * 可以使用 VS Code 的标准 Diff 工具查看变更。
  * Deno 代码变成了标准的 `.ts` 文件，可以被其他 Deno 脚本 import 或 lint。

---

### 方案三：更好的 Diff 工具 (nbdime)

**适用场景**：你必须提交输出结果（例如教学课件、数据分析报告），但深受冲突之苦。

#### 1. 安装与配置

```bash
pip install nbdime
nbdime config-git --enable --global
```

#### 2. 使用效果

* `git diff` 会自动调用 `nbdiff`，以网页或友好的终端形式展示 Notebook 的差异（图片差异也能看）。
* `git merge` 会自动调用 `nbmerge`，智能处理 JSON 结构的合并。

---

### 针对不同语言的具体配置总结

#### Python 环境最佳实践

1. **项目根目录配置 `.pre-commit-config.yaml`** (团队协作神器)：
    如果你在团队中，不要依赖每个人手动配置 `nbstripout`，使用 `pre-commit` 钩子：

    ```yaml
    repos:
    -   repo: https://github.com/kynan/nbstripout
        rev: 0.6.1
        hooks:
        -   id: nbstripout
    ```

2. **结合 Jupytext**：
    将 Notebook 保存为 `py:percent` 格式，Git 仅追踪 `.py` 文件，Diff 阅读体验极佳。

#### Deno (TypeScript/JavaScript) 环境最佳实践

Deno 用户面临的主要问题是生态工具多基于 Python。即使你用 Deno Kernel，也建议安装一个 Python 虚拟环境来辅助 Git 管理。

1. **环境准备**：
    确保安装了 `pip install jupytext nbstripout`。

2. **Jupytext 配置 (关键)**：
    在项目根目录创建 `jupytext.toml` 配置文件，全局设定映射规则：

    ```toml
    # jupytext.toml
    # 默认将所有 ipynb 关联为 typescript script
    default_jupytext_formats = "ipynb,ts:percent"
    ```

3. **Git 忽略规则 (.gitignore)**：
    如果你决定完全通过 Jupytext 管理，可以忽略 ipynb：

    ```text
    # .gitignore
    *.ipynb
    .ipynb_checkpoints/
    ```

    或者，如果你想保留 ipynb 作为入口，但在 Git 中保持干净：
    * 配置 `nbstripout` (见方案一)。
    * 提交 `your_script.ts` (由 Jupytext 生成) 用于 Review。
    * 提交 `your_script.ipynb` (已清除输出) 用于在该环境直接运行。

---

### 终极建议流程图

**场景 A：个人开发 / 必须保留图表输出**
> 使用 **nbdime**。
> `git diff` 变得可视化，不再痛苦。

**场景 B：团队协作 / 工程化项目 (Python & Deno)**
>
> 1. 安装 **nbstripout** (通过 pre-commit 钩子强制执行)。
> 2. 安装 **Jupytext**。
> 3. **Python**: 生成 `.py` 对应文件。
> 4. **Deno**: 生成 `.ts` 对应文件。
> 5. **Git**: 提交 `.py/.ts` (用于看 diff 和 review) + 提交 `.ipynb` (必须是 stripped 过的，仅作为启动入口)。

### 现代 IDE 的原生支持 (VS Code)

如果你使用 VS Code，现在它已经内置了很好的 Notebook Diff 支持。

* 在 Source Control 面板点击修改过的 `.ipynb` 文件，VS Code 会打开一个专门的 **Rich Diff Editor**，左边是旧版，右边是新版，能清晰看到代码块和输出的变化。
* **注意**：这只解决了“看”的问题，没解决“仓库体积”和“合并冲突”的问题。所以 **nbstripout 依然是必须的**。
