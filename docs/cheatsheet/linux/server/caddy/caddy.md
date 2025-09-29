
### Caddy 服务器 (Cheatsheet)

Caddy 是一款功能强大、易于配置的开源 Web 服务器，以其自动 HTTPS 功能而闻名。这份备忘单旨在提供常用命令和配置片段的快速参考。

#### 1. 安装 (Installation)

Caddy 提供了多种安装方式，以下是一些常见系统的方法。

**Linux (Debian, Ubuntu, Raspbian):**

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

**Linux (Fedora, CentOS, RedHat):**

```bash
sudo dnf install 'dnf-command(copr)'
sudo dnf copr enable @caddy/caddy
sudo dnf install caddy
```

**macOS (使用 Homebrew):**

```bash
brew install caddy
```

**Windows (使用 Scoop 或 Choco):**

```bash
# Scoop
scoop install caddy

# Chocolatey
choco install caddy
```

**Docker:**

```bash
docker pull caddy
```

更多安装方式请参考 [官方安装文档](https://caddyserver.com/docs/install)。

#### 2. 核心命令 (Core Commands)

这些命令通常在您的 Caddyfile 所在目录运行。

| 命令 | 描述 |
| :--- | :--- |
| `caddy run` | 在前台启动 Caddy。会阻塞当前终端，日志直接输出到标准输出。 |
| `caddy start` | 在后台以守护进程模式启动 Caddy。 |
| `caddy stop` | 优雅地停止后台运行的 Caddy 服务。 |
| `caddy reload` | 平滑地加载新的配置，服务不会中断。这是更新配置最常用的方式。 |
| `caddy validate` | 验证 Caddyfile 配置文件的语法是否正确。 |
| `caddy fmt` | 格式化 Caddyfile，使其更整洁、规范。 |
| `caddy version` | 显示 Caddy 的版本信息。 |

#### 3. Caddyfile 基础

Caddyfile 是配置 Caddy 的最简单方式。

**基本结构:**

```caddy
<站点地址> {
    <指令> <参数>
}
```

- **站点地址 (Site Address):** 您的域名、IP 地址或端口，例如 `example.com`, `localhost:8080`, `:443`。
- **指令 (Directive):** Caddy 提供的功能模块，例如 `file_server`, `reverse_proxy`, `respond`。
- **参数 (Arguments):** 指令的具体配置。

**一个最简单的 "Hello, World!" 示例:**

```caddy
localhost:8080

respond "Hello, world!"
```

将以上内容保存为 `Caddyfile`，然后在该目录下运行 `caddy run`，访问 `http://localhost:8080` 即可看到结果。

#### 4. 常见配置用例 (Common Use Cases)

**a) 静态网站服务器**

托管一个静态网站（HTML, CSS, JS 文件）。

```caddy
example.com {
    # 设置网站根目录
    root * /var/www/html
  
    # 启用文件服务器
    file_server
}
```

*Caddy 会为 `example.com` 自动申请并配置 HTTPS 证书。*

**b) 反向代理 (Reverse Proxy)**

将请求转发到后端的另一个服务（例如 Node.js, Python, Java 应用）。

```caddy
example.com {
    # 将所有请求代理到本地 3000 端口的服务
    reverse_proxy localhost:3000
}
```

**c) 带有负载均衡的反向代理**

将流量分发到多个后端服务。

```caddy
example.com {
    reverse_proxy 192.168.1.101:80 192.168.1.102:80 {
        # 负载均衡策略 (可选, 默认为 random)
        # 可选值: random, round_robin, least_conn, first, ip_hash
        lb_policy round_robin
    }
}
```

**d) PHP 网站 (例如 WordPress, Laravel)**

```caddy
example.com {
    root * /var/www/public
  
    # 启用 PHP-FPM
    php_fastcgi unix//run/php/php8.1-fpm.sock
  
    file_server
}
```

**e) 配置日志 (Logging)**

自定义日志的格式和输出位置。

```caddy
example.com {
    log {
        output file /var/log/caddy/example.com.access.log {
            # 自动轮转日志文件
            roll_size     10MiB
            roll_keep     10
            roll_keep_for 720h
        }
        format console  # 使用更易读的格式
    }

    reverse_proxy localhost:3000
}
```

**f) 添加自定义响应头 (Headers)**

```caddy
example.com {
    header {
        # 添加 Strict-Transport-Security 头，增强安全性
        Strict-Transport-Security "max-age=31536000;"
      
        # 添加自定义头
        X-My-Header "Hello from Caddy"
      
        # 移除不希望暴露的头
        -Server
    }

    reverse_proxy localhost:3000
}
```

**g) Gzip/Zstd 压缩**

Caddy 默认开启了 `zstd` 和 `gzip` 压缩，您也可以精细化控制。

```caddy
example.com {
    # 开启压缩，并指定内容类型
    encode zstd gzip
  
    file_server
}
```

**h) URL 重写 (Rewrite) 和重定向 (Redirect)**

```caddy
example.com {
    # 永久重定向 (301)
    redir /old-page /new-page
  
    # 将所有 www 请求重定向到根域名
    @www host www.example.com
    redir @www https://example.com{uri}
  
    # URL 重写，对用户透明
    # 常用于单页应用 (SPA)
    try_files {path} /index.html

    file_server
}
```

---
更多高级用法和指令，请查阅 [Caddy 官方文档](https://caddyserver.com/docs/)。
