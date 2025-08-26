# Linux环境变量配置指南

## 什么是环境变量

环境变量是操作系统中用来指定系统运行环境的一些参数，它们包含了系统运行时需要的各种信息，如路径、用户信息、系统配置等。

## 常见环境变量

- `PATH`: 决定了shell在哪些目录中寻找命令或程序
- `HOME`: 当前用户的主目录
- `USER`: 当前用户名
- `SHELL`: 当前使用的shell
- `PWD`: 当前工作目录
- `LANG`: 系统语言和区域设置
- `TERM`: 终端类型

## 环境变量配置文件

### 全局配置文件（对所有用户生效）

- `/etc/environment`: 系统级环境变量配置
- `/etc/profile`: 系统级登录shell配置文件
- `/etc/bash.bashrc`: 系统级非登录shell配置文件

### 用户配置文件（仅对当前用户生效）

- `~/.profile`: 用户登录shell配置文件
- `~/.bash_profile`: 用户bash登录shell配置文件
- `~/.bashrc`: 用户bash非登录shell配置文件
- `~/.bash_login`: 用户登录shell配置文件

## 环境变量操作命令

### 查看环境变量

```bash
# 查看所有环境变量
env
printenv

# 查看特定环境变量
echo $PATH
echo $HOME

# 查看所有环境变量（包括shell变量）
set
```

### 设置环境变量

```bash
# 临时设置（仅对当前shell会话有效）
export VAR_NAME=value
export PATH=$PATH:/new/path

# 永久设置（需要写入配置文件）
# 在 ~/.bashrc 或 ~/.profile 中添加
export VAR_NAME=value
export PATH=$PATH:/new/path
```

### 删除环境变量

```bash
# 临时删除
unset VAR_NAME

# 永久删除需要从配置文件中移除并重新加载
```

## 配置文件加载顺序

1. 登录shell：
   - `/etc/profile`
   - `~/.profile` 或 `~/.bash_profile` 或 `~/.bash_login`
   - `~/.bashrc`（通常在~/.profile中被调用）

2. 非登录shell：
   - `/etc/bash.bashrc`
   - `~/.bashrc`

## 重新加载配置文件

```bash
# 重新加载配置文件，使更改立即生效
source ~/.bashrc
# 或
. ~/.bashrc

# 重新加载profile
source ~/.profile
# 或
. ~/.profile
```

# Linux环境变量配置Cheatsheet

## 基本操作

| 操作 | 命令 | 示例 |
|------|------|------|
| 查看所有环境变量 | `env` 或 `printenv` | `env` |
| 查看特定环境变量 | `echo $VAR_NAME` | `echo $PATH` |
| 临时设置环境变量 | `export VAR_NAME=value` | `export JAVA_HOME=/usr/lib/jvm/java-11-openjdk` |
| 临时追加到PATH | `export PATH=$PATH:/new/path` | `export PATH=$PATH:/usr/local/go/bin` |
| 临时删除环境变量 | `unset VAR_NAME` | `unset TEMP_VAR` |
| 重新加载配置文件 | `source ~/.bashrc` 或 `. ~/.bashrc` | `source ~/.bashrc` |

## 配置文件

| 文件 | 作用范围 | 加载时机 |
|------|----------|----------|
| `/etc/environment` | 全局 | 系统启动时 |
| `/etc/profile` | 全局 | 用户登录时 |
| `/etc/bash.bashrc` | 全局 | 启动非登录shell时 |
| `~/.profile` | 当前用户 | 用户登录时 |
| `~/.bash_profile` | 当前用户 | 用户登录时（bash） |
| `~/.bashrc` | 当前用户 | 启动非登录shell时 |
| `~/.bash_login` | 当前用户 | 用户登录时（如果~/.bash_profile不存在） |

## 常用环境变量配置示例

### Java环境变量

```bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$PATH:$JAVA_HOME/bin
```

### Python环境变量

```bash
export PYTHONPATH=$PYTHONPATH:/path/to/python/modules
export PATH=$PATH:/path/to/python/bin
```

### Node.js环境变量

```bash
export NODE_ENV=production
export PATH=$PATH:/path/to/node/bin
```

### Go环境变量

```bash
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
```

### 自定义环境变量

```bash
export MY_APP_HOME=/path/to/my/app
export MY_APP_CONFIG=$MY_APP_HOME/config
```

## 检查环境变量配置

```bash
# 检查PATH中是否包含某个目录
echo $PATH | grep -q "/usr/local/bin" && echo "Found" || echo "Not found"

# 检查环境变量是否设置
if [ -z "$VAR_NAME" ]; then
    echo "VAR_NAME is not set"
else
    echo "VAR_NAME is set to $VAR_NAME"
fi
```

## 最佳实践

1. **用户级配置优先**：优先在用户配置文件中设置环境变量，避免影响其他用户
2. **使用~/.bashrc**：对于日常使用的环境变量，建议在~/.bashrc中设置
3. **PATH变量管理**：添加新路径时使用`$PATH:/new/path`格式，保留原有PATH
4. **配置文件组织**：将相关环境变量配置放在一起，便于管理
5. **注释说明**：在配置文件中添加注释，说明每个环境变量的用途
6. **测试验证**：修改配置文件后，使用`source`命令重新加载并测试
