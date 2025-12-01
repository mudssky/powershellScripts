# Nginx 配置管理

该目录采用 `sites-available / sites-enabled` 管理模式，提供模板与脚本以安全启用/禁用 Nginx 配置，并实现 Ollama 的安全反向代理。

## 目录结构
- `sites-available/`：存放仓库维护的 Nginx 配置模板（未必启用）
- `enableNginxConf.ps1`：在本仓库中启用指定模板的 CLI 脚本
- `Manage-NginxConf.psm1`：模块导出函数（启用/禁用/校验/重载/htpasswd）
- `Manage-NginxConf.ps1`：同功能的脚本版（可直接 dot-source 使用）


## 先决条件
- 已安装 Nginx
- 若使用 Basic Auth：安装 `htpasswd`（Debian/Ubuntu: `apache2-utils`；RHEL/CentOS: `httpd-tools`）
- Ollama 建议监听 `127.0.0.1:11434`，外部访问通过 Nginx 代理

### 安装方式（按发行版）
- Debian/Ubuntu：
  ```bash
  sudo apt update && sudo apt install -y nginx apache2-utils
  sudo systemctl enable --now nginx
  sudo nginx -t && sudo systemctl reload nginx
  ```
- RHEL/CentOS（如需 `EPEL` 请先启用）：
  ```bash
  sudo yum install -y nginx httpd-tools
  sudo systemctl enable --now nginx
  sudo nginx -t && sudo systemctl reload nginx
  ```
- Fedora：
  ```bash
  sudo dnf install -y nginx httpd-tools
  sudo systemctl enable --now nginx
  sudo nginx -t && sudo systemctl reload nginx
  ```
- Arch Linux：
  ```bash
  sudo pacman -Syu nginx apache
  sudo systemctl enable --now nginx
  sudo nginx -t && sudo systemctl reload nginx
  ```

## 快速启用示例
### Basic Auth
```powershell
sudo pwsh -File ./config/nginx/enableNginxConf.ps1 -Name ollama-basic -BasicUser ollama -BasicPassword 'your-secret'
```
访问验证：
```bash
curl -u ollama:your-secret http://<host>/api/tags
curl -u ollama:your-secret http://localhost/api/tags
```

### Bearer Token
将模板中的 `my-secret-token` 替换为你的令牌后执行：
```powershell
sudo pwsh -File ./config/nginx/enableNginxConf.ps1 -Name ollama-bearer
```
访问验证：
```bash
curl -H "Authorization: Bearer my-secret-token" http://<host>/api/tags
```

## 常用函数（模块）
如需在交互式会话中使用函数：
```powershell
Import-Module ./config/nginx/Manage-NginxConf.psm1
Test-NginxConfig
Enable-NginxConf -Name ollama-basic
Disable-NginxConf -Name ollama-basic
Reload-Nginx
New-NginxHtpasswd -User ollama -Password 'your-secret'
```

## 生效配置管理
- 列出已启用配置：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action ListEnabled
  ```
- 列出已安装配置：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action ListAvailable
  ```
- 查看配置内容（来源可选 available/enabled/repo）：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action Show -Name ollama-basic -Source available
  ```
- 移除安装的配置（同时删除启用链接需加 `-Force`）：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action RemoveAvailable -Name ollama-basic -Force
  ```
- 验证配置综合生效（可选提供 URL 与认证参数做 HTTP 冒烟测试）：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action Verify -Name ollama-basic -Url http://<host>/api/tags -BasicUser ollama -BasicPassword 'your-secret'
  ```
- 单次端点测试（不关联配置名）：
  ```powershell
  pwsh -File ./config/nginx/manage.ps1 -Action TestEndpoint -Url http://<host>/api/tags -BasicUser ollama -BasicPassword 'your-secret'
  ```

## 运维建议
- 每次变更前先运行 `Test-NginxConfig`（底层等同 `nginx -t`）
- 使用平滑重载而非重启：`Reload-Nginx`
- 生产环境中封禁 `11434/tcp`，只暴露 `80/443`
- `.htpasswd` 权限建议 `600` 或 `640`

## 故障排查
- 启用失败：查看 `nginx -t` 输出或系统日志（`/var/log/nginx/error.log`）
- `htpasswd` 不存在：按“先决条件”安装对应工具
- Bearer 令牌不生效：确认请求头格式精确为 `Authorization: Bearer <token>`
- 开放访问（无认证，仅反向代理）：
  ```powershell
  sudo pwsh -File ./config/nginx/enableNginxConf.ps1 -Name ollama-open
  ```
  警告：此配置不带任何认证，务必确保 Ollama 监听 `127.0.0.1:11434` 且外网仅能通过 Nginx 访问，必要时用防火墙限制来源。
