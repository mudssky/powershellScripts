# nginx cheatsheet

## 1. 常用 CLI 命令

**服务管理 (Systemd)**
```bash
systemctl start nginx       # 启动
systemctl stop nginx        # 停止
systemctl restart nginx     # 重启
systemctl reload nginx      # 重载配置 (不中断连接)
systemctl status nginx      # 查看状态
systemctl enable nginx      # 开机自启
```

**Nginx 二进制命令**
```bash
nginx -t                    # 测试配置文件语法是否正确 (非常重要！)
nginx -T                    # 测试配置并打印出解析后的完整配置
nginx -s reload             # 平滑重载配置
nginx -s stop               # 快速停止
nginx -s quit               # 优雅停止 (处理完请求后停止)
nginx -v                    # 查看版本
nginx -V                    # 查看版本及编译参数 (查看安装了哪些模块)
```

**文件路径 (常见默认值)**
*   **主配置文件**: `/etc/nginx/nginx.conf`
*   **子配置文件目录**: `/etc/nginx/conf.d/` 或 `/etc/nginx/sites-enabled/`
*   **日志目录**: `/var/log/nginx/`
*   **默认 Web 根目录**: `/usr/share/nginx/html` 或 `/var/www/html`

---

## 2. 基础 HTTP 服务配置

**静态网站服务器**
```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    root /var/www/example.com; # 项目根目录
    index index.html index.htm;

    # 处理前端单页应用 (SPA) 路由
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 自定义 404 页面
    error_page 404 /404.html;
}
```

---

## 3. 反向代理 (Reverse Proxy)

**基础反向代理 (转发到后端应用)**
```nginx
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://localhost:3000; # 转发目标
        
        # 传递客户端真实 IP 和头部信息
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**WebSocket 代理支持**
```nginx
location /ws/ {
    proxy_pass http://localhost:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

---

## 4. 负载均衡 (Load Balancing)

**配置 Upstream**
```nginx
upstream backend_servers {
    # 负载均衡策略 (默认是轮询)
    # ip_hash;                 # 根据 IP 哈希 (保持会话)
    # least_conn;              # 最少连接数优先
    
    server 10.0.0.1:8080 weight=3; # 权重越高，流量越大
    server 10.0.0.2:8080;
    server 10.0.0.3:8080 backup;   # 备用节点 (仅当其他节点挂掉时启用)
}

server {
    listen 80;
    server_name app.example.com;

    location / {
        proxy_pass http://backend_servers;
    }
}
```

---

## 5. SSL/HTTPS 配置

**启用 HTTPS 并强制跳转**
```nginx
# 1. 强制 HTTP 跳转到 HTTPS
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

# 2. HTTPS 配置
server {
    listen 443 ssl http2; # 启用 HTTP/2
    server_name example.com;

    ssl_certificate /etc/nginx/ssl/example.com.crt;
    ssl_certificate_key /etc/nginx/ssl/example.com.key;

    # 推荐的安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    location / {
        root /var/www/html;
    }
}
```

---

## 6. 重定向与重写 (Redirect & Rewrite)

**常用跳转**
```nginx
# 301 永久重定向 (SEO 友好)
return 301 https://new-domain.com$request_uri;

# 302 临时重定向
return 302 /maintenance.html;
```

**Rewrite 规则**
```nginx
# 将 /old-page.html 重写为 /new-page
rewrite ^/old-page\.html$ /new-page permanent;

# 去掉 www (www.example.com -> example.com)
if ($host ~* ^www\.(.*)) {
    return 301 $scheme://$1$request_uri;
}
```

---

## 7. Location 匹配优先级

优先级从高到低：

1.  `=`  : 精确匹配 (停止搜索)
2.  `^~` : 前缀匹配 (如果匹配，停止搜索正则)
3.  `~`  : 正则匹配 (区分大小写)
4.  `~*` : 正则匹配 (不区分大小写)
5.  `/`  : 通用前缀匹配

**示例：**
```nginx
location = / {
    # 只匹配 /
}

location ^~ /static/ {
    # 匹配 /static/ 开头的路径，并不再检查正则
}

location ~ \.(gif|jpg|png)$ {
    # 匹配图片结尾
}

location / {
    # 兜底规则
}
```

---

## 8. 安全与访问控制

**隐藏版本号**
在 `http` 块中添加：
```nginx
server_tokens off;
```

**IP 黑白名单**
```nginx
location /admin/ {
    allow 192.168.1.0/24; # 允许内网
    deny all;             # 拒绝其他所有
}
```

**跨域设置 (CORS)**
```nginx
location /api/ {
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    
    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

**禁止特定文件访问**
```nginx
location ~ /\.ht {
    deny all;
}
```

---

## 9. 常用内置变量

| 变量名 | 描述 |
| :--- | :--- |
| `$host` | 请求行中的主机名或 Host 头 |
| `$request_uri` | 包含参数的原始 URI (如 `/search?q=nginx`) |
| `$uri` | 不带参数的 URI (如 `/search`) |
| `$remote_addr` | 客户端 IP 地址 |
| `$http_user_agent` | 客户端 User-Agent |
| `$scheme` | 协议 (http 或 https) |
| `$upstream_response_time` | 上游服务器响应时间 |
| `$status` | 响应状态码 (200, 404 等) |

---

## 10. 常见陷阱

1.  **root vs alias**:
    *   `root`: 会将 location 路径**追加**到 root 路径后。
    *   `alias`: 会用 alias 路径**替换** location 路径。
    ```nginx
    # 请求 /static/img.png -> /var/www/static/img.png
    location /static/ { root /var/www; } 

    # 请求 /static/img.png -> /var/www/images/img.png
    location /static/ { alias /var/www/images/; }
    ```
2.  **缺少分号**: 每行指令必须以 `;` 结尾。
3.  **if 是邪恶的**: 尽量避免在 `location` 中使用 `if`，除非你非常清楚自己在做什么（通常用 `try_files` 或 `rewrite` 替代）。