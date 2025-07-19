好的，这是一个为你精心整理的 fzf (fuzzy finder) 使用技巧速查表 (Cheatsheet)。你可以将它保存下来，方便随时查阅。

---

### **fzf 速查表 (Cheatsheet)**

#### **1. 基础快捷键 (Shell 集成)**

**暂无powershell集成 2025年7月10日 星期四 13:53:00**

| 快捷键 | 功能 | 描述 |
| :--- | :--- | :--- |
| **`Ctrl` + `T`** | 查找文件 / 目录 | 将选中的文件/目录路径插入到光标处 |
| **`Ctrl` + `R`** | 搜索命令历史 | 模糊搜索并执行历史命令 |
| **`Alt` + `C`** | 快速切换目录 | 模糊搜索目录并 `cd` 进去 |

---

#### **2. fzf 交互界面内按键**

| 按键 | 功能 | 描述 |
| :--- | :--- | :--- |
| `Ctrl`+`J` / `↓` | 向下移动 | |
| `Ctrl`+`K` / `↑` | 向上移动 | |
| **`Enter`** | **确认选择** | |
| `Ctrl`+`C` / `Ctrl`+`G` / `Esc` | 退出 | 取消操作 |
| **`Tab`** | **多选（标记）** | 配合 `-m` 选项使用，向下标记 |
| **`Shift`+`Tab`** | **多选（反向标记）** | 向上标记/取消标记 |
| `Ctrl`+`A` | 全选 | |
| `Ctrl`+`D` | 全部取消 | |
| `?` | 帮助 | 显示/隐藏快捷键帮助 |

---

#### **3. 核心用法：管道 (`|`) 与 `xargs`**

fzf 的精髓在于处理来自管道 (`|`) 的任何列表数据。

```bash
# 语法: <产生列表的命令> | fzf | <处理 fzf 输出的命令>

# 示例：
# 1. 交互式地查看文件内容
cat $(find . -type f | fzf)

# 2. 使用 xargs 将选择项传递给命令
find . -type f | fzf | xargs bat # 使用 bat 预览选中的文件
```

---

#### **4. 强大选项 (Flags)**

| 选项 | 别名 | 功能 | 示例 |
| :--- | :--- | :--- | :--- |
| **`--preview 'cmd'`** | | **实时预览窗口**，`{}` 是占位符，代表当前选中行 | `ls \| fzf --preview 'bat {}'` |
| **`-m`** | `--multi` | **开启多选模式**，配合 `Tab` 键使用 | `ls \| fzf -m` |
| `--height XX%` | | 设置 fzf 窗口高度 | `--height 50%` |
| `--layout=reverse` | | 列表显示在底部，输入框在顶部 | `fzf --layout=reverse` |
| `--border` | | 为 fzf 窗口添加边框 | `fzf --border` |
| `--query 'str'` | `-q 'str'` | 启动时预填充搜索内容 | `fzf -q '.js'` |
| `--bind 'key:action'` | | 自定义快捷键绑定 | `--bind 'ctrl-p:toggle-preview'` |

---

#### **5. 实战配方 (Recipes)**

将这些配方添加为 alias 或 function，极大提升效率。

**Git 操作**

```bash
# 交互式切换 Git 分支 (包括远程分支)
git branch -a | fzf | xargs git checkout

# 交互式查看并检出 Git commit 记录
git log --oneline --graph --all | fzf --preview 'git show --color=always $(echo {} | cut -d " " -f 1)' | awk '{print $1}' | xargs git checkout

# 交互式选择文件并 git add (预览 diff)
git status -s | fzf -m --preview "git diff --color=always -- {+2}" | awk '{print $2}' | xargs git add
```

**进程管理**

```bash
# 交互式杀死进程 (fkill)
ps -ef | sed 1d | fzf -m | awk '{print $2}' | xargs kill -9
```

**目录 & 文件**

```bash
# 快速进入子目录 (替代 Alt+C)
cd $(find * -type d -maxdepth 2 | fzf)

# 查找文件并用 Vim 打开 (推荐使用 fd)
fd . | fzf --preview 'bat --color=always {}' | xargs vim
```

**SSH 连接**

```bash
# 从 ~/.ssh/config 中选择主机并连接
grep '^Host ' ~/.ssh/config | awk '{print $2}' | fzf | xargs ssh
```

---

#### **6. 全局配置 (放入 `.bashrc` 或 `.zshrc`)**

```bash
# 1. 设置默认命令源 (推荐 fd 或 rg，比 find 快)
#    fd - 查找文件
#    rg --files - 查找 Git 项目中的文件
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'

# 2. 设置默认选项 (外观、预览、快捷键等)
export FZF_DEFAULT_OPTS='
--height 40% --layout=reverse --border
--preview "([[ -d {} ]] && tree -C {} | head -50) || (bat --color=always --plain {})"
--bind "ctrl-p:toggle-preview"
--color="hl:148,hl+:154,pointer:032,marker:010"'
```

**核心思想：组合与创造！** fzf 是一个强大的“连接器”，你可以将任何命令行工具的输出通过它变成一个交互式菜单。
