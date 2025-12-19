在实际项目（特别是数据科学、机器学习或研发项目）中，JupyterLab 如果使用不当，很容易变成“代码垃圾场”：变量满天飞、执行顺序混乱、无法版本控制。

为了让 JupyterLab 成为生产力工具而不是累赘，以下是经过工业界验证的**最佳实践指南**：

### 1. 项目结构标准化 (Project Structure)

不要把数据、代码、模型全部堆在一个文件夹里。推荐采用类似 [Cookiecutter Data Science](https://drivendata.github.io/cookiecutter-data-science/) 的结构：

* **`notebooks/`**: 存放 `.ipynb` 文件。命名最好带编号，如 `01_data_cleaning.ipynb`, `02_eda.ipynb`，明确执行顺序。
* **`src/` (或 `scripts/`)**: 存放核心逻辑的 `.py` 文件（函数、类）。
* **`data/`**: 分层管理，如 `raw/` (原始数据，只读), `processed/` (清洗后的数据)。
* **`outputs/`**: 存放生成的图表、模型权重文件。

### 2. 核心工作流：从 Notebook 到 Script (Refactoring)

这是最重要的习惯：**Notebook 用来探索，Script 用来生产**。

* **拒绝“复制粘贴”**：如果你发现同一个函数需要在两个 Notebook 里使用，**千万不要复制**。
* **重构流程**：
    1. 在 Notebook 里写代码验证想法。
    2. 一旦代码跑通且逻辑通用，将其提炼成函数或类，剪切到 `src/` 下的 `.py` 文件中。
    3. 在 Notebook 里 `import` 该函数使用。
* **神器：Autoreload**：
    在 JupyterLab 中，修改了外部 `.py` 文件通常需要重启内核才能生效。为了避免这个麻烦，请在每个 Notebook 的第一个单元格加上：

    ```python
    %load_ext autoreload
    %autoreload 2
    ```

    这样你修改 `.py` 文件后，Notebook 会自动热更新，无需重启。

### 3. 版本控制 (Git) 的痛点与解法

Notebook 本质是巨大的 JSON 文件，包含图片和元数据，直接用 Git 管理非常痛苦（Diff 乱码、冲突难修）。

* **策略 A：提交前清除输出 (Clear Output)**
  * 养成习惯：`Edit` -> `Clear All Outputs` 再 Commit。
  * 或者使用 `nbstripout` 工具，自动在 git add 时过滤掉输出内容。
* **策略 B：使用 Jupytext (强烈推荐)**
  * 安装 `jupytext` 插件。它可以让 Notebook 自动同步保存一份 `.py` 或 `.md` 文件。
  * **做法**：Git 只管理同步生成的 `.py` 文件（纯代码，Diff 清晰），忽略 `.ipynb`。
  * **好处**：你可以用 VS Code 或 PyCharm 强大的重构功能去编辑这个同步的 `.py` 文件，JupyterLab 里的 Notebook 会自动更新。

### 4. 环境管理 (Kernels)

不要所有项目都用系统自带的 Python。

* **每个项目一个虚拟环境**：使用 `conda` 或 `venv` 创建独立环境。
* **注册 Kernel**：
    将虚拟环境注册到 Jupyter 中，确切知道自己在跑哪个环境：

    ```bash
    python -m ipykernel install --user --name=my_project_env --display-name "Python (My Project)"
    ```

* **固化依赖**：项目根目录必须有 `requirements.txt` 或 `environment.yml`，保证别人能跑通你的 Notebook。

### 5. 利用 JupyterLab 的 IDE 特性

不要把它仅仅当成网页版 Notebook 用，要利用它的 IDE 功能：

* **分屏协作 (Split View)**：
  * 左边放 `src/utils.py`（文本编辑器模式），右边放 `notebook.ipynb`。一边修改底层库，一边在 Notebook 里测试。
* **目录插件 (Table of Contents)**：
  * JupyterLab 左侧栏自带目录功能。务必使用 Markdown 的 `#` 标题来组织 Notebook，保持文档结构清晰。
* **变量检查器 (Variable Inspector)**：
  * 右键点击 Notebook -> `Open New Output View` 或者安装变量检查插件，实时监控内存中的变量，防止内存泄漏。

### 6. 必装的生产力插件 (Extensions)

现在的 JupyterLab (v3/v4) 安装插件非常容易（pip 即可）：

* **`jupyterlab-lsp`**: 提供类似 VS Code 的代码自动补全、跳转定义、错误提示（Linting）。
* **`jupyterlab-code-formatter` (搭配 Black)**: 一键美化代码格式，保持代码风格统一。
* **`jupyter-resource-usage`**: 在状态栏显示 CPU 和 内存使用情况，防止数据过大撑爆机器。

### 7. 可复现性 (Reproducibility)

为了防止“我的电脑上能跑，你的不行”或者“昨天能跑，今天不行”：

* **Restart & Run All**：在提交代码前，必须点击 `Kernel` -> `Restart Kernel and Run All Cells`。确保你的代码不是依赖于某种随机的执行顺序（比如你在第 10 格定义了变量，却在第 2 格用了它，因为你来回跳着执行过）。
* **固定随机种子 (Random Seed)**：涉及机器学习或随机采样的，务必在开头固定 Seed。

### 总结

**高阶玩家的 JupyterLab 看起来是这样的**：
左侧是清晰的文件夹结构，屏幕中间左半部分是封装好的 `.py` 脚本，右半部分是简洁的 `.ipynb`（只包含加载数据、调用函数、分析图表），Git 记录清晰，代码格式统一。
