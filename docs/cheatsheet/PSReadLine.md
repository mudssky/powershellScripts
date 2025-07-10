# PSReadLine 备忘录

`PSReadLine` 是一个 PowerShell 模块，它极大地增强了 PowerShell 的命令行交互体验。可以说，**它是现代 PowerShell 之所以如此好用的核心原因之一**。它就像是为你的命令行配备了一个强大的智能代码编辑器。

如果你正在使用 Windows 10/11 自带的 PowerShell 5.1，或者安装了 PowerShell 7，那么 PSReadLine 已经**默认安装并启用**了。

下面是 PSReadLine 的核心功能以及如何使用它们，从最常用到更高级的技巧。

---

### 1. 检查与更新 PSReadLine

首先，你可以确认一下你正在使用的版本。

```powershell
# 查看 PSReadLine 模块信息
Get-Module -ListAvailable PSReadLine

# 更新到最新版本 (建议以管理员身份运行 PowerShell)
Update-Module -Name PSReadLine
```

保持最新版本可以让你获得最好的功能和性能。

---

### 2. 核心功能与使用方法

#### **A. 语法高亮 (Syntax Highlighting)**

这是你一打开 PowerShell 就能看到的功能。

* **功能**：不同的命令元素（Cmdlet、参数、字符串、变量、操作符等）会显示不同的颜色。
* **好处**：
  * **可读性强**：命令结构一目了然。
  * **即时纠错**：如果你输入时引号没有闭合，后面的所有文本都会变成字符串的颜色，你马上就能发现错误。

**如何使用**：无需任何操作，它是自动启用的。

#### **B. 智能提示与自动补全 (IntelliSense & Tab Completion)**

这是提高效率的**关键功能**。

* **Tab 自动补全**：
  * 输入命令的一部分，按 `Tab` 键，它会自动补全命令、参数名、文件名和路径。
  * 连续按 `Tab` 可以在多个匹配项之间循环切换。
  * **示例**：输入 `Get-S` 然后按 `Tab`，它可能会补全为 `Get-ScheduledJob`，再按一下可能变成 `Get-ScheduledTask`。

* **菜单式补全 (Menu Completion)**：
  * 按 `Ctrl` + `Space` 会弹出一个可交互的菜单，列出所有可能的补全选项。
  * **这比反复按 `Tab` 效率高得多！**
  * **示例**：输入 `Get-Process -Name`，然后按 `Ctrl` + `Space`，它会列出所有正在运行的进程名供你选择。

#### **C. 强大的命令历史记录 (Command History)**

PSReadLine 极大地增强了对历史命令的访问能力。

* **上下箭头 `↑` / `↓`**：浏览你输入过的所有历史命令（这是最基本的）。

* **部分匹配搜索**：
  * 输入命令的开头几个字母，比如 `Get-P`。
  * 然后按 `F8` (向后搜索) 或 `Shift` + `F8` (向前搜索)，它只会在以 `Get-P` 开头的历史命令中循环。

* **关键字反向搜索 (Ctrl+R)**：
  * 这是**最强大的历史搜索功能**，尤其适合查找很久以前的复杂命令。
  * 按 `Ctrl` + `R`，然后开始输入你记忆中命令的**任意部分**（不一定是开头）。
  * PSReadLine 会动态地显示第一个匹配的历史命令。
  * 持续按 `Ctrl` + `R` 会在所有匹配项中向后循环。
  * 找到后，按 `Enter` 执行，或按 `左右箭头` 进行修改。

    **示例**：按 `Ctrl+R`，然后输入 `process`，它可能会找到 `Get-Process -Name "chrome"`。

#### **D. 预测式智能提示 (Predictive IntelliSense / Ghost Text)**

这是 PSReadLine 2.1.0 版本后引入的“杀手级”功能。

* **功能**：在你输入时，它会根据你的历史记录，用**浅灰色文本**（幽灵文本）预测你可能要输入的完整命令。
* **如何使用**：
  * 如果预测正确，只需按 **`右箭头 →`** 或 `End` 键即可接受并补全整行命令。
  * 如果预测不准，直接忽略它，继续输入即可。

这个功能默认是开启的。如果你的没有，可以手动开启：

```powershell
Set-PSReadLineOption -PredictionSource History
```

#### **E. 高效的行内编辑快捷键 (Editing Shortcuts)**

PSReadLine 让你像在文本编辑器中一样编辑命令。

* **`Home` / `End`**：移动光标到行首/行尾。
* **`Ctrl` + `←` / `→`**：按单词移动光标。
* **`Ctrl` + `Backspace`**：删除光标前的一个单词。
* **`Ctrl` + `Delete`**：删除光标后的一个单词。
* **`Alt` + `.`**：粘贴上一条命令的最后一个参数，非常有用！

#### **F. 多行编辑 (Multi-line Editing)**

当你需要输入或粘贴一段多行脚本时，不用担心。

* **功能**：使用 `Shift` + `Enter` 可以在不执行命令的情况下换行。这允许你在控制台中编写完整的 `if` 语句、`foreach` 循环等。
* **自动识别**：当你粘贴多行代码时，PSReadLine 通常能自动识别并正确处理，不会立即执行。

#### **G. 命令未找到建议 (Command Not Found Suggestion)**

这就是你最初遇到的那个提示。

* **功能**：当你输入的命令拼写错误或不存在时，它会使用模糊匹配算法，为你推荐最相似的正确命令。
* **好处**：快速纠正拼写错误，无需重新完整输入。

---

### 3. 自定义你的 PSReadLine

你可以通过 `Set-PSReadLineOption` 命令来个性化你的 PSReadLine 体验。为了让设置永久生效，可以把它们添加到你的 PowerShell 配置文件 `$PROFILE` 中。

1. **打开配置文件**：

    ```powershell
    notepad $PROFILE
    ```

    (如果文件不存在，它会提示你创建)

2. **添加自定义设置**：在文件中添加你想要的配置，例如：

    ```powershell
    # 启用历史记录预测
    Set-PSReadLineOption -PredictionSource History

    # 设置编辑模式为 Windows 风格 (默认) 或 Emacs/Vi
    Set-PSReadLineOption -EditMode Windows

    # 当命令执行完成时，如果屏幕滚动了，则清屏
    # Set-PSReadLineOption -HistoryNoDuplicates # 不保存重复的历史命令

    # 自定义语法高亮颜色
    Set-PSReadLineOption -Colors @{
        Command     = 'Green'
        Parameter   = 'Yellow'
        String      = 'Magenta'
        Comment     = '#666666' # 灰色注释
    }
    ```

3. **保存文件并重启 PowerShell**，你的设置就会生效。

### 总结

掌握 PSReadLine 是从 PowerShell 新手走向高手的关键一步。它能极大地提升你的工作效率，减少错误，并让使用命令行成为一种享受。

**建议你从以下几点开始练习：**

1. 多使用 `Tab` 和 `Ctrl` + `Space` 进行补全。
2. 尝试用 `Ctrl` + `R` 搜索你以前用过的命令。
3. 习惯使用 `右箭头` 接受预测建议。

希望这份详细的指南对你有帮助！
