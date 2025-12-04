对于 Python 而言，实现“单文件、带依赖、跨平台、直接执行”的脚本，长期以来是一个痛点。但随着 **PEP 723 (Inline Script Metadata)** 标准的通过以及 **`uv`** 这种现代化工具的出现，Python 现在终于有了类似 Deno 的**最佳实践**。

目前的最佳方案是：**使用 PEP 723 标准声明依赖，并配合 `uv` (或 `pipx`) 进行运行时管理。**

---

### 方案一：现代化最佳实践 (使用 `uv` + PEP 723)

这是目前最接近 Deno/Shell 体验的方案。
**核心原理**：在 Python 文件头部使用注释块声明依赖。运行时，工具会自动创建一个临时的（或缓存的）虚拟环境，安装依赖，然后执行脚本。

#### 1. 安装工具

推荐使用 **[uv](https://github.com/astral-sh/uv)**，它是目前最快、最好用的 Python 包管理/运行工具（Rust 编写）。

```bash
# MacOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
# 或者使用 pip
pip install uv
```

#### 2. 编写脚本 (`script.py`)

利用 PEP 723 格式，在文件头部写入依赖：

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests",
#     "rich",
# ]
# ///

import sys
import requests
from rich.console import Console
from rich.panel import Panel

def main():
    console = Console()
    
    # 1. 使用第三方库 (requests)
    try:
        resp = requests.get("https://httpbin.org/get")
        data = resp.json()
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}")
        return

    # 2. 使用第三方库 (rich) 打印漂亮输出
    console.print(Panel.fit(
        f"[bold green]Hello from Python Script![/bold green]\n"
        f"User-Agent: {data['headers']['User-Agent']}\n"
        f"Platform: {sys.platform}",
        title="Cross Platform Script"
    ))

if __name__ == "__main__":
    main()
```

#### 3. 执行方式

**Linux / macOS:**
依靠 Shebang (`#!/usr/bin/env -S uv run`) 实现直接执行。

```bash
chmod +x script.py
./script.py
```

*系统会自动调用 `uv`，`uv` 会解析脚本里的依赖，瞬间创建虚拟环境并运行，无需手动 pip install。*

**Windows:**
Windows 不支持 Shebang 直接运行（除非安装了特殊的 Launcher），推荐直接用命令调用：

```powershell
uv run script.py
```

---

### 方案二：标准兼容方案 (使用 `pipx`)

如果你的环境不允许安装 `uv`，或者更倾向于使用 Python 官方推荐的工具，可以使用 **`pipx`**。它也支持 PEP 723 标准（需要 1.4.0+ 版本）。

#### 1. 编写脚本 (`script_pipx.py`)

代码内容与上面完全一致，只是 Shebang 可以改得更通用一点（或者不写 Shebang，手动调用）。

```python
#!/usr/bin/env -S pipx run
# /// script
# dependencies = ["requests", "rich"]
# ///

import requests
# ... (代码同上)
```

#### 2. 执行方式

**通用执行 (Windows/Linux/Mac):**

```bash
pipx run script_pipx.py
```

*注意：`pipx` 的速度比 `uv` 慢不少，因为它创建虚拟环境的过程较慢。而 `uv` 几乎是毫秒级的。*

---

### 方案三：打包为独立二进制 (PyInstaller/Nuitka)

如果你不能要求对方安装 `uv` 或 `pipx`，甚至不能要求对方有 Python 环境，那么唯一的“单文件”方案就是**编译**。

#### 1. 编写脚本

正常编写，无需特殊的 Shebang 或 Metadata 注释。

#### 2. 编译

推荐使用 **Nuitka** (编译成 C 代码，速度快，反编译难) 或 **PyInstaller** (打包运行时)。

```bash
# 安装 Nuitka
pip install nuitka

# 编译为单文件 (Linux/Mac 生成二进制，Windows 生成 .exe)
python -m nuitka --onefile --follow-imports script.py
```

#### 3. 执行

直接分发生成的二进制文件。

* **优点**：目标机器零依赖。
* **缺点**：文件体积大（几十 MB 起步）；需要针对不同平台分别编译（在 Windows 上编译出 exe，在 Linux 上编译出 binary）。

---

### 总结：Python 跨平台脚本最佳实践对比

| 特性 | **uv run (PEP 723)** <br> <span style="color:green">★ 强烈推荐</span> | **pipx run** | **PyInstaller / Nuitka** |
| :--- | :--- | :--- | :--- |
| **单文件源码** | ✅ 支持 (依赖写在注释里) | ✅ 支持 | ✅ (源码需编译) |
| **依赖管理** | **自动** (极速，临时环境) | **自动** (较慢) | **编译时打包** |
| **执行速度** | 极快 (Rust 驱动) | 较慢 (Python 驱动) | 快 (无需解释器启动) |
| **目标环境要求** | 需安装 `uv` | 需安装 `pipx` | **零依赖** |
| **跨平台源码** | ✅ 代码拷过去就能跑 | ✅ 代码拷过去就能跑 | ❌ 需分平台编译 |
| **Shebang 支持** | ✅ `#!/usr/bin/env -S uv run` | ✅ `#!/usr/bin/env -S pipx run` | 无需 |

### 最终建议

1. **首选方案**：使用 **PEP 723 格式** + **`uv`**。
    * 它解决了 Python 脚本长期以来“必须先建 venv 再 pip install”的繁琐流程。
    * 它让 Python 脚本拥有了类似 Shell/Deno 的“即插即用”体验。

2. **Windows 兼容技巧**：
    * 在 Windows 上，虽然不能直接 `./script.py`，但你可以创建一个同名的 `script.bat` 或 `script.cmd` 放在旁边：

        ```batch
        @uv run "%~dp0script.py" %*
        ```

    * 这样在 Windows 命令行里也可以直接输入 `script` 回车执行了。
