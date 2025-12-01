## 目标
- 在 `\home\administrator\projects\env\powershellScripts\config\nginx` 存放并维护多个 Nginx 配置文件，采用“sites-available / sites-enabled”模式（方案二）。
- 提供一个 PowerShell 7+ 脚本，支持：将仓库内某个 `.conf` 文件复制到 `/etc/nginx/sites-available/` 并创建到 `/etc/nginx/sites-enabled/` 的软链接，使其生效；完成 Ollama 的反向代理首个需求（可选 Basic Auth 或 Bearer Token）。
- 所有变更先进行 `nginx -t` 语法校验，再执行平滑重载。

## 目录与文件布局
- `config/nginx/方案.md`：管理方案说明（已存在，采用方案二）。
- `config/nginx/需求.md`：安全与认证选项说明（已存在）。
- 新增（仓库内模板）：
  - `config/nginx/sites-available/ollama-basic.conf`：Ollama 反代 + Basic Auth 模板。
  - `config/nginx/sites-available/ollama-bearer.conf`：Ollama 反代 + Bearer Token 校验模板。
- 新增（脚本）：
  - `linux/Manage-NginxConf.ps1`：导出多个函数用于启用/禁用/校验/重载 Nginx 配置。

## 脚本设计（PowerShell 7+）
- 导出函数（Verb-Noun）：
  - `Enable-NginxConf`：将仓库内指定 `.conf` 安装到 `/etc/nginx/sites-available/<name>` 并在 `sites-enabled` 建立软链接；校验并重载。
  - `Disable-NginxConf`：删除 `/etc/nginx/sites-enabled/<name>` 链接，保留 `sites-available` 原文件；校验并重载。
  - `Test-NginxConfig`：执行 `nginx -t` 并输出结果。
  - `Reload-Nginx`：执行 `systemctl reload nginx` 或 `nginx -s reload`（按系统优先级选择）。
  - `Start-Nginx`：如果未运行则启动 `nginx` 服务。
  - `New-NginxHtpasswd`：辅助生成或更新 `/etc/nginx/.htpasswd`（参考 `需求.md`）。
- 核心参数：
  - `-Name`（必填）：配置名（不带扩展名），如 `ollama-basic`。
  - `-RepoConfPath`（可选）：仓库中 `.conf` 模板路径，默认 `config/nginx/sites-available/<Name>.conf`。
  - `-OverwriteAvailable`（可选）：如目标 `sites-available/<Name>` 已存在是否覆盖。
  - `-UseSystemctl`（可选）：优先使用 `systemctl` 控制 Nginx，默认自动探测。
  - 认证辅助：`New-NginxHtpasswd` 接受 `-User`、`-Password`、`-FilePath`（默认 `/etc/nginx/.htpasswd`）。
- 运行权限：脚本涉及 `/etc/nginx` 写入与服务控制，需以 `sudo pwsh` 或具有相应权限运行。

## 模板内容（仓库内）
- `ollama-basic.conf`（重点片段）：
  - `server { listen 80; server_name _; location / { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; proxy_pass http://127.0.0.1:11434; ... } }`
  - 与 `需求.md` 建议保持一致，确保请求仅经 Nginx 进入；后端 Ollama 建议监听 `127.0.0.1:11434`。
- `ollama-bearer.conf`（重点片段）：
  - 在 `location /` 使用 `if ($http_authorization != "Bearer <your-token>") { return 401; }`；其余 `proxy_pass` 与基本头一致。
- 命名规范：文件名与用途一致，例如 `ollama-basic.conf`；域名版本可在后续模板扩展（`server_name ai.example.com;`）。

## 启用流程（方案二）
- 选择并确认仓库内模板：`config/nginx/sites-available/<Name>.conf`。
- 使用脚本：
  - `Enable-NginxConf -Name <Name>` → 复制至 `/etc/nginx/sites-available/<Name>` → 建立 `/etc/nginx/sites-enabled/<Name>` 软链接。
  - 自动执行 `nginx -t` → 通过则 `Reload-Nginx`；不通过则回滚链接并报告错误。
- 禁用：`Disable-NginxConf -Name <Name>` → 删除链接 → `Reload-Nginx`。

## 验证与自检
- 语法校验：每次启用/禁用前后强制 `nginx -t`。
- 访问验证：
  - Basic Auth：`curl -u ollama:<password> http://<host>/api/tags` 应 200；未带凭证应 401。
  - Bearer Token：`curl -H "Authorization: Bearer <token>" http://<host>/api/tags` 应 200；错误/缺失应 401。
- 服务检查：如使用 `systemctl`，检查 `systemctl status nginx`；失败时提供诊断输出。

## 安全注意事项
- 将 Ollama 监听地址改回 `127.0.0.1:11434`，确保外网仅能通过 Nginx 访问。
- 启用后建议用防火墙封禁 `11434/tcp`（仅保留 80/443）。
- `.htpasswd` 文件权限设为仅 root 可读（`chmod 640`/`600`）。

## 兼容性与回滚
- 脚本在校验失败时自动移除新建软链接并恢复原状态。
- 支持覆盖模式：当 `-OverwriteAvailable` 指定时允许更新 `/etc/nginx/sites-available/<Name>`。

## 交付物
- `linux/Manage-NginxConf.ps1`（含完整函数与帮助注释）。
- `config/nginx/sites-available/ollama-basic.conf` 模板。
- `config/nginx/sites-available/ollama-bearer.conf` 模板。
- 使用文档片段（示例命令与说明）整合至 `config/nginx/方案.md` 或 README。

## 后续扩展
- 支持 `server_name`、`listen`、`ssl` 参数化生成模板（如需域名与 HTTPS）。
- 增加 `Test-OllamaProxy` 冒烟测试函数（脚本内通过 `Invoke-WebRequest`）。
- 集成日志路径与限速/防爆破策略（`limit_req`）。