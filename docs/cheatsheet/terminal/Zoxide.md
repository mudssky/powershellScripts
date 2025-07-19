`zoxide` 是一个非常高效的智能目录跳转工具，它能记住你访问过的目录，并使用 "frecency" 算法（结合了**频率 (frequency)** 和**新近度 (recency)**）快速跳转。

掌握以下技巧，可以让你的 `zoxide` 使用体验更上一层楼，极大地提升终端操作效率。

### 1. 核心基础技巧

这是 `zoxide` 最常用、最基本的功能。

#### **基础跳转 `z <keyword>`**

这是最核心的命令。`zoxide` 会在你的历史记录中，根据关键字匹配最 "frecent" 的目录。

```bash
# 假设你经常访问 /home/user/projects/web-app
# 你可以这样跳转：
z web
z app
z pro # 如果这是你最常访问的 'pro' 相关目录
```

**技巧点**：关键字不需要是目录的开头，可以是路径中任意部分的子字符串。

#### **交互式选择 `z -i`**

当一个关键字匹配到多个目录时，这非常有用。`zoxide` 会弹出一个可供选择的列表（通常需要 `fzf` 或类似工具支持，效果最佳）。

```bash
# 假设你有 /home/user/projects/web-app 和 /var/www/web-app
z -i web
# 会出现一个列表让你选择：
# > /home/user/projects/web-app
#   /var/www/web-app
```

**技巧点**：这是解决模糊匹配冲突的最佳方式。

### 2. 进阶匹配技巧

这些技巧让你能更精确地控制跳转目标。

#### **多关键字匹配**

你可以提供多个关键字，`zoxide` 会按顺序在路径中进行匹配。

```bash
# 假设你想跳转到 /home/user/projects/rust-project/src
z proj rust src
```

**技巧点**：这比单个模糊的关键字更精确，能有效缩小搜索范围。

#### **跳转到子目录 `z <keyword> / <sub-dir>`**

这是一个超级实用的技巧！先用 `z` 找到父目录，然后直接进入其下的子目录。

```bash
# 假设你经常访问 /home/user/projects/my-api
# 现在想直接进入它的 src/controllers 目录
z my-api / src/controllers
```

**技巧点**：无需分两步 `cd`，一条命令直达深层目录。

### 3. 与其他命令联动（杀手级技巧）

`zoxide` 不仅仅是 `cd` 的替代品，它的查询功能可以和任意 Shell 命令组合，威力倍增。

#### **查询路径 `zoxide query` (或别名 `zq`)**

`zq` 不会跳转，而是**打印出**匹配度最高的路径。这可以配合命令替换 `$(...)` 来使用。

```bash
# 查看项目目录下的文件，而不用先进去
ls $(zq proj)

# 用 vim/vscode 打开项目里的某个文件
vim $(zq my-api)/main.go
code $(zq my-web)

# 复制整个项目目录
cp -r $(zq old-proj) /path/to/backup/
```

#### **交互式查询 `zoxide query -i` (或别名 `zi`)**

与 `z -i` 类似，但它不跳转，而是将你选择的路径打印出来，方便与其他命令配合。

```bash
# 在多个匹配项中选择一个，然后用 vim 打开
vim $(zi proj)
```

**技巧点**：`zq` 和 `zi` 是 `zoxide` 从“一个好用的跳转工具”升级为“终端效率神器”的关键。强烈建议为它们设置别名：

```bash
# 在你的 .bashrc, .zshrc 等配置文件中添加
alias zq='zoxide query'
alias zi='zoxide query -i'
```

### 4. 数据库管理技巧

了解如何管理 `zoxide` 的数据，能让它更符合你的习惯。

#### **查看数据库列表 `zoxide query -l`**

列出所有记录在案的目录及其得分（score）。这有助于你理解为什么 `z` 会跳转到某个特定的地方。

```bash
zoxide query -l
# 输出示例:
# 100.25  /home/user/projects/web-app
# 80.50   /etc/nginx
# 50.00   /var/log
```

**技巧点**：当你对 `z` 的跳转结果感到困惑时，用这个命令来排查问题。

#### **手动添加目录 `zoxide add` (或别名 `za`)**

有时你希望将一个目录立即加入 `zoxide` 的高优先级列表，即使你还没怎么访问过它。

```bash
# 将当前目录添加进去
zoxide add .

# 添加一个指定目录
zoxide add /path/to/important/dir
```

#### **手动移除目录 `zoxide remove` (或别名 `zr`)**

如果你不希望某个目录再出现在 `zoxide` 的候选项中（比如一个已删除的项目）。

```bash
zoxide remove /path/to/old/project
```

**技巧点**：定期清理无用的路径，能让你的跳转更加清爽准确。同样，可以设置别名：

```bash
alias za='zoxide add'
alias zr='zoxide remove'
```

### 5. 与 FZF 的完美融合

`zoxide` 和 `fzf`（一个命令行模糊查找器）是天作之合。安装 `fzf` 后，`zoxide` 的交互模式 `-i` 会自动使用它，带来无与伦比的体验。

你可以通过环境变量 `_ZO_FZF_OPTS` 来定制 `fzf` 的外观和行为。

```bash
# 示例：在 .zshrc 或 .bashrc 中设置
# --height: fzf 窗口高度
# --layout: 预览窗口位置
export _ZO_FZF_OPTS="--height 40% --layout=reverse --preview 'ls -la {}'"
```

**技巧点**：这个设置会让你在选择目录时，能实时预览该目录下的文件，非常方便。

### 总结：实用技巧清单

| 场景 | 命令 | 解释 |
| :--- | :--- | :--- |
| **日常跳转** | `z proj` | 跳转到最匹配 "proj" 的目录。 |
| **选择困难** | `z -i web` | 当 "web" 匹配多个时，弹出列表供选择。 |
| **精确打击** | `z proj api` | 匹配路径中同时包含 "proj" 和 "api" 的目录。 |
| **直达深处** | `z proj / src` | 跳转到 `proj` 目录下的 `src` 子目录。 |
| **只看不进** | `ls $(zq proj)` | 列出 `proj` 目录内容，但不进入。 |
| **远程编辑** | `vim $(zq proj)/config.yaml` | 直接用 Vim 打开 `proj` 目录下的文件。 |
| **感到困惑** | `zoxide query -l` | 查看所有历史记录和得分，排查问题。 |
| **清理门户** | `zoxide remove /old/proj` | 从数据库中移除一个不再使用的目录。 |
| **强制安利** | `zoxide add /new/proj` | 手动将一个新目录加入数据库。 |

熟练运用以上这些技巧，尤其是 `zq` 与其他命令的结合，能让 `zoxide` 成为你命令行工具箱中最锋利的一把瑞士军刀。
