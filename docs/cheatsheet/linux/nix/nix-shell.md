这份 `nix-shell` 速查表涵盖了从临时环境搭建到编写可复用开发环境脚本的常用命令和模式。

### 🚀 快速开始 (Ad-hoc 模式)

无需编写配置文件，直接在命令行启动包含特定工具的 Shell。

```bash
# 进入包含 git 和 vim 的环境
nix-shell -p git vim

# 启动环境并运行单条命令（运行完自动退出）
nix-shell -p python3 --run "python3 --version"

# 指定特定版本的 Python
nix-shell -p python311

# 进入环境，但尽可能隔离宿主机的环境变量（更纯净）
nix-shell -p git --pure
```

---

### 📁 项目开发环境 (`shell.nix`)

在项目根目录创建 `shell.nix` 文件，定义开发环境依赖。

#### 1. 基础模板 (`mkShell`)

这是定义开发环境的标准方式。

```nix
# shell.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  # 进入 Shell 时可用的包
  packages = [
    pkgs.nodejs_20
    pkgs.yarn
    pkgs.git
  ];

  # 环境变量设置
  NIX_ENFORCE_PURITY = 0;
  MY_ENV_VAR = "hello-world";

  # Shell 启动钩子（自动执行的命令）
  shellHook = ''
    echo "欢迎进入开发环境！"
    echo "Node version: $(node -v)"
  '';
}
```

#### 2. 启动环境

在包含 `shell.nix` 的目录下运行：

```bash
nix-shell
```

*(如果 `shell.nix` 不存在，它会尝试寻找 `default.nix`)*

---

### 📜 脚本 Shebang (自包含脚本)

编写可以自动下载依赖并运行的脚本，无需手动安装环境。

#### Python 示例

```python
#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.requests

import requests
print(requests.get("https://nixos.org").status_code)
```

#### Bash 示例

```bash
#! /usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq

# 这个脚本运行时会自动拥有 curl 和 jq
curl -s https://api.github.com/repos/nixos/nix | jq '.stargazers_count'
```

**参数说明：**

* `-i <interpreter>`: 指定实际执行脚本的解释器（如 `python3`, `bash`）。
* `-p <packages>`: 指定依赖包。

---

### 📌 常用参数详解

| 参数 | 简写 | 说明 | 示例 |
| :--- | :--- | :--- | :--- |
| `--packages` | `-p` | 定义临时环境中需要的包 | `nix-shell -p go` |
| `--command` | | 启动 Shell，执行命令，**不退出** Shell（常用于调试） | `nix-shell --command "export FOO=bar"` |
| `--run` | | 启动 Shell，执行命令，**执行完退出** | `nix-shell --run "make build"` |
| `--pure` | | 清除绝大部分宿主机环境变量（除了 `$HOME`, `$USER` 等），确保环境纯净 | `nix-shell --pure` |
| `--interpreter` | `-i` | 指定脚本解释器 | `nix-shell -i bash` |
| `--keep` | | 在 `--pure` 模式下保留特定的宿主机环境变量 | `nix-shell --pure --keep SSH_AUTH_SOCK` |
| `--include` | `-I` | 添加/覆盖 Nix 搜索路径（常用于固定 nixpkgs 版本） | 见下文“固定版本” |

---

### 🔒 进阶技巧

#### 1. 固定 Nixpkgs 版本 (Reproducibility)

为了防止不同时间运行 `nix-shell` 得到不同版本的软件，建议在 `shell.nix` 中固定 nixpkgs 的 commit hash。

```nix
let
  # 使用特定的 commit hash 固定 nixpkgs 版本
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/0672315759b3e15e2121365f067c1c8c56bb4722.tar.gz";
  pkgs = import nixpkgs {};
in
pkgs.mkShell {
  packages = [ pkgs.hello ];
}
```

或者在命令行中临时指定：

```bash
nix-shell -p hello -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/master.tar.gz
```

#### 2. 使用 Flakes (现代替代方案)

如果你启用了 Nix Flakes，通常使用 `nix develop` 替代 `nix-shell`，但 `nix-shell` 依然兼容。

```bash
# 传统的 nix-shell
nix-shell -p git

# 对应的 Flake 命令 (需开启 experimental-features)
nix shell nixpkgs#git
# 或者进入开发环境
nix develop
```

#### 3. 嵌套 Shell

你可以在 `nix-shell` 内部再运行 `nix-shell`，但这通常意味着你的环境配置可能过于复杂。如果需要组合多个环境，建议在 `mkShell` 中合并 `packages` 列表。
