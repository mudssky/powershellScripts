## 目标
- 在 `config/nginx` 目录下，提供列出生效配置、查看配置、移除配置，以及验证配置生效的完整功能集。
- 保持与现有方案二（sites-available/sites-enabled）一致的工作流，并复用当前模块结构。

## 现状
- 已有函数：`Enable-NginxConf`、`Disable-NginxConf`、`Start-Nginx`、`Reload-Nginx`、`Test-NginxConfig`、`New-NginxHtpasswd`（位于 `Manage-NginxConf.psm1`）。
- 缺失：生效配置列表、查看配置内容、移除 `sites-available` 文件、实际路由/代理的启用验证。

## 新增函数设计（PowerShell 7+）
### 列出配置
- `Get-NginxEnabledConfs`
  - 描述：列出 `/etc/nginx/sites-enabled` 中的所有启用配置，返回名称、链接目标、存在性。
  - 返回：`PSCustomObject[]`（`Name`、`EnabledPath`、`AvailablePath`、`IsSymlink`、`TargetExists`）。
- `Get-NginxAvailableConfs`
  - 描述：列出 `/etc/nginx/sites-available` 中的所有已安装配置，返回名称与路径。
  - 返回：`PSCustomObject[]`（`Name`、`AvailablePath`）。

### 查看配置
- `Get-NginxConfContent -Name <name> [-Source available|enabled|repo]`
  - 描述：读取指定配置的内容；`available` 读取系统文件，`enabled` 读取启用链接指向文件，`repo` 读取仓库模板（`config/nginx/sites-available/<name>.conf`）。
  - 返回：`string`（完整文本）。

### 移除配置
- `Remove-NginxConf -Name <name> [-Force]`
  - 描述：移除 `/etc/nginx/sites-available/<name>` 文件；若 `sites-enabled` 存在链接则先提示或在 `-Force` 下自动删除链接再移除文件。
  - 行为：变更前执行 `Test-NginxConfig`（预检）；变更后执行 `Reload-Nginx`。

### 验证生效
- `Verify-NginxConf -Name <name>`
  - 描述：验证配置是否“生效”包含三步：
    1. `sites-enabled/<name>` 软链接存在且目标文件存在。
    2. `nginx -t` 语法校验通过。
    3. 可选：HTTP 冒烟测试（当提供 `-Url` 及认证参数时）。
  - 返回：`PSCustomObject`（`HasSymlink`、`TargetExists`、`SyntaxOk`、`HttpOk`、`Diagnostics`）。
- `Test-NginxEndpoint -Url <http://...> [-BasicUser <u>] [-BasicPassword <p>] [-BearerToken <t>] [-TimeoutSec <n>]`
  - 描述：对目标 URL 进行 HTTP 冒烟测试，支持 Basic Auth 或 Bearer Token；返回状态码与响应片段。
  - 返回：`PSCustomObject`（`StatusCode`、`Success`、`BodyPreview`、`Error`）。

## CLI 入口脚本扩展
- 新增 `config/nginx/manage.ps1`（或扩展 `enableNginxConf.ps1`）提供统一动作入口：
  - 参数：`-Action`（`Enable|Disable|ListEnabled|ListAvailable|Show|RemoveAvailable|Verify|TestEndpoint`）、`-Name`、`-Source`、`-Url`、`-BasicUser`、`-BasicPassword`、`-BearerToken`、`-TimeoutSec`、`-OverwriteAvailable`、`-UseSystemctl`、`-DryRun`。
  - 输出：尽量结构化（对象）+ 人类可读文本。

## 安全与回滚
- 删除配置前校验与提示，默认仅删除 `enabled` 链接，删除 `available` 需显式调用或 `-Force`。
- 所有写操作失败时记录原因并保持系统在一致状态（例如在 `nginx -t` 失败时自动回滚软链接）。

## 验证与文档
- 验证：
  - `Get-NginxEnabledConfs` 与 `Get-NginxAvailableConfs` 返回预期列表。
  - `Verify-NginxConf -Name ollama-basic` 在启用后报告全绿；未启用时给出具体失败项。
  - `Test-NginxEndpoint` 对 `http://<host>/api/tags` 在携带认证下返回 200。
- 文档：更新 `config/nginx/README.md`，增加上述命令示例与常见故障。

## 交付物
- 更新 `Manage-NginxConf.psm1`：新增 5 个函数及帮助注释。
- 新增 `config/nginx/manage.ps1` CLI。
- 更新 `README.md`：使用说明与示例。