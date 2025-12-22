
---

# Zellij Cheatsheet

## 🚀 命令行启动 (CLI)

| 命令 | 说明 |
| :--- | :--- |
| `zellij` | 启动一个新的会话 |
| `zellij a` (或 `attach`) | 恢复最近的一个会话 |
| `zellij a <name>` | 恢复指定名称的会话 |
| `zellij ls` | 列出所有后台会话 |
| `zellij delete-all-sessions` | **慎用**：删除所有会话 |
| `zellij --layout <file>` | 使用指定布局文件启动 |
| `zellij options --simple-ui` | 启动简化UI（隐藏花哨的面板框） |

---

## 🎮 全局控制 (Global)

Zellij 默认情况下，所有的快捷键都以 `Ctrl` 开头。

| 快捷键 | 模式 | 说明 |
| :--- | :--- | :--- |
| **`Ctrl + g`** | **Lock (锁定)** | **最重要！** 锁定/解锁 Zellij。锁定后，按键直接发送给终端（用于 vim/tmux/ssh）。 |
| `Ctrl + p` | Pane (面板) | 进入面板管理模式 |
| `Ctrl + t` | Tab (标签) | 进入标签页管理模式 |
| `Ctrl + n` | Resize (调整) | 进入大小调整模式 |
| `Ctrl + s` | Scroll (滚动) | 进入滚动/搜索模式 |
| `Ctrl + o` | Session (会话) | 进入会话管理模式 |
| `Ctrl + h` | Move (移动) | 进入移动面板模式 |
| `Ctrl + q` | Quit | 退出当前模式或关闭程序（取决于上下文） |

---

## ⚡ 快捷导航 (Direct Navigation - Alt)

除了模态操作（按 `Ctrl` 进入特定模式），Zellij 提供了一套 **“快捷导航” (Direct Navigation)** 键位，通常使用 `Alt` 键。这些快捷键可以直接执行动作，无需先切换模式。

这在 Zellij 中被称为 **"Secondary Modifier"** (辅助修饰键) 操作。

### 1. 🔲 面板操作 (Panes)

最常用的操作，无需进入 `Ctrl + p` 模式：

* **`Alt + n`**：新建面板 (New Pane) —— *这是最常用的快捷键*。
* **`Alt + f`**：切换 **浮动窗口** (Toggle Floating Pane) —— *非常实用的技巧，把当前面板变成悬浮窗*。
* **`Alt + h` / `j` / `k` / `l`**：向左/下/上/右移动焦点。
* **`Alt + ←` / `↓` / `↑` / `→`**：(同上) 使用方向键移动焦点。

### 2. 📐 调整大小 (Resize)

无需进入 `Ctrl + n` 模式：

* **`Alt + =`** (或 `+`)：放大当前面板。
* **`Alt + -`**：缩小当前面板。

### 3. 📑 标签页操作 (Tabs)

默认情况下，Zellij 的标签页快捷键主要集中在 `Ctrl + t` 模式下，但也有一些快捷方式：

* **`Alt + [`** (左方括号)：切换到上一个标签页 (Previous Tab)。
* **`Alt + ]`** (右方括号)：切换到下一个标签页 (Next Tab)。

*(注意：如果这组快捷键在你的终端不生效，可能是被终端模拟器拦截了，或者你需要检查你的版本是否为最新版)*

---

### 💡 为什么有时候 `Alt` 键没反应？

这是一个常见坑点，尤其是在 **macOS** 上。

* **macOS iTerm2 用户**：默认情况下 `Option` (Alt) 键会输出特殊字符（比如 `Alt+n` 可能会打出 `~`）。
  * **解决方法**：去 iTerm2 设置 -> `Profiles` -> `Keys` -> `General` -> 将 `Left Option Key` 设置为 **`Esc+`**。
* **VSCode 终端用户**：VSCode 可能会拦截 Alt 键用于菜单栏导航。

### 🔍 如何查看所有当前快捷键？

如果你想确认你的 Zellij 具体绑定了什么键，可以在命令行运行：

```bash
zellij setup --check
```

这会列出所有当前的配置诊断信息，包括按键绑定状态。

---

## 🔲 Pane 模式 (按 `Ctrl + p` 进入)

> 此模式下用于管理当前屏幕内的分屏。

| 按键 | 动作 | 备注 |
| :--- | :--- | :--- |
| `n` | **New** | 新建面板 (默认向右或向下) |
| `d` | **Down** | 向下分屏新建 |
| `r` | **Right** | 向右分屏新建 |
| `x` | **Close** | 关闭当前面板 |
| `f` | **Fullscreen** | 切换当前面板全屏 |
| `z` | **Frames** | 切换面板边框显示/隐藏 |
| `w` | **Floating** | **切换悬浮窗口 (画中画模式)** |
| `e` | **Embed** | 将悬浮窗口嵌入回平铺布局 |
| `p` | **Next** | 切换焦点到下一个面板 |
| `Arrows` | Move Focus | 上下左右切换焦点 |

---

## 📑 Tab 模式 (按 `Ctrl + t` 进入)

> 此模式下用于管理顶部的标签页。

| 按键 | 动作 | 备注 |
| :--- | :--- | :--- |
| `n` | **New** | 新建标签页 |
| `x` | **Close** | 关闭当前标签页 |
| `r` | **Rename** | 重命名当前标签页 |
| `s` | **Sync** | **同步模式** (在一个面板输入，所有面板同步执行) |
| `Left`/`Right`| Switch | 切换上/下一个标签页 |
| `1` - `9` | Go to | 直接跳转到第 N 个标签页 |
| `Tab` | Toggle | 在最近两个标签页之间切换 |

---

## 📜 Scroll 模式 (按 `Ctrl + s` 进入)

> 类似 Vim 的浏览模式，用于查看历史输出。

| 按键 | 动作 | 备注 |
| :--- | :--- | :--- |
| `j` / `Down` | Scroll Down | 向下滚动 |
| `k` / `Up` | Scroll Up | 向上滚动 |
| `PgUp` / `PgDn` | Page | 翻页 |
| `/` | **Search** | 进入搜索模式 (按 `n`/`N` 查找下一个/上一个) |
| `e` | **Edit** | **神器**：在默认编辑器($EDITOR)中打开当前滚动缓冲区 |
| `Ctrl + c` | Cancel | 退出搜索或滚动模式 |

---

## 🔌 Session 模式 (按 `Ctrl + o` 进入)

| 按键 | 动作 | 备注 |
| :--- | :--- | :--- |
| `d` | **Detach** | **分离会话** (Zellij 仍在后台运行，你回到 Shell) |
| `w` | **Manager** | 打开交互式会话管理器 (可视化的切换/重命名会话) |

---

## 📐 Resize 模式 (按 `Ctrl + n` 进入)

| 按键 | 动作 |
| :--- | :--- |
| `Arrows` | 向对应方向增加/减少尺寸 |
| `+` / `-` | 智能增大/减小当前面板 |

---

## 🛠️ 配置文件与布局

* **默认配置路径**: `~/.config/zellij/config.kdl`
* **导出默认配置**:

    ```bash
    zellij setup --dump-config > ~/.config/zellij/config.kdl
    ```

* **布局文件路径**: `~/.config/zellij/layouts/`

### 常用布局示例 (layout.kdl)

```kdl
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=2 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
    tab name="Code" focus=true {
        pane command="nvim"
    }
    tab name="Terminal" {
        pane split_direction="vertical" {
            pane
            pane command="htop"
        }
    }
}
```

## ✨ 实用小技巧

1. **快速复制**: 在任何模式下，按住 `Shift` (或根据终端设置按住 `Option`/`Alt`) 使用鼠标选中文本即可复制。
2. **嵌套使用**: 如果你在 Zellij 里 SSH 到服务器，服务器里也开了 Zellij/Tmux，请按 **`Ctrl + g`** 锁定外层的 Zellij，这样按键才能传给里层的会话。
3. **临时任务**: 使用 `Ctrl + p` -> `w` 呼出悬浮窗处理 `git commit` 或 `npm install`，处理完再按 `Ctrl + p` -> `w` 隐藏，保持桌面整洁。
