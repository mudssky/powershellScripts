# 目标

* 在现有仓库新增一份 macOS 专用配置文件，保持与 Windows 配置等效，并为后续在 macOS 运行 Gitea 提供一致的目录结构与参数。

# 影响面分析

* 修改/新增文件: `config/gitea/custom/conf/mac-app.ini`

* 运行影响: 仅当在 macOS 使用该配置启动 Gitea 时生效，不影响 Windows 运行。

* 风险点: 目录路径不一致、权限/所有者不正确、密钥与数据库迁移一致性。

# 设计要点（Windows → macOS 差异）

* 路径规范: 统一改为 POSIX 路径（`/Users/<user>/...`），避免使用盘符与反斜杠。

* 运行用户: 设置为 macOS 的账户（示例使用 `mudssky`，可按需调整）。

* 工作目录: `WORK_PATH` 作为所有数据与 `custom` 的根，遵循官方约定（参考: Configuration Cheat Sheet 与 app.example.ini）。

* 数据库: 继续使用 `sqlite3`，直接迁移 `data/gitea.db` 即可；如未来切换 MySQL/Postgres，再调整对应段。

* 仓库/LFS/日志: 路径与 Windows 保持对应结构（`data/gitea-repositories`、`data/lfs`、`log`）。

* 秘钥: 保持与现有实例一致（`LFS_JWT_SECRET`、`INTERNAL_TOKEN`、`oauth2.JWT_SECRET`），以确保迁移后令牌与签名兼容；如为全新实例，建议重新生成。

* 启动方式: 使用 `--config` 指向 `mac-app.ini`，或将其重命名为默认 `app.ini` 放在 `custom/conf/` 下。

参考文档:

* 官方配置速查: <https://docs.gitea.com/administration/config-cheat-sheet>

* app.ini 示例: <https://github.com/go-gitea/gitea/blob/main/custom/conf/app.example.ini>

# 实施步骤

1. 在仓库新增 `config/gitea/custom/conf/mac-app.ini`（内容见下文）。
2. 在 macOS 创建工作目录: `/Users/mudssky/coding/gitea`（如需使用其他用户或路径，请替换）。
3. 创建子目录: `data/`、`log/`、`data/lfs`、`data/gitea-repositories`。
4. 迁移数据:

   * 复制 Windows 下的 `data/gitea.db` 到 macOS 的 `data/gitea.db`。

   * 复制 `data/gitea-repositories/` 与 `data/lfs/` 内容至对应位置。
5. 权限/所有者:

   * 确保上述目录与文件的所有者为 macOS 运行账户（示例 `mudssky`）。
6. 启动验证:

   * 使用 `gitea --work-path /Users/mudssky/coding/gitea --config /Users/mudssky/coding/gitea/custom/conf/mac-app.ini` 启动。

   * 访问 `http://localhost:30001/` 并检查 `Site Administration → Configuration` 中的 `CustomConf`、路径与版本信息。

# 验证清单

* 能够打开首页与登录页面。

* 通过 HTTP/SSH 克隆与推送（SSH 端口默认 22）。

* LFS 正常（上传/下载）。

* 日志写入到 `/Users/mudssky/coding/gitea/log`。

* 现有仓库与用户数据完整可见。

# 安全注意

* 如为全新部署，建议重新生成 `INTERNAL_TOKEN`、`LFS_JWT_SECRET` 与 `[oauth2].JWT_SECRET`（避免在不同环境复用）。

* 迁移完成后，限制配置文件访问权限（仅运行用户可读）。

# 拟新增文件内容（macOS）

```ini
APP_NAME = Gitea: Git with a cup of tea
RUN_USER = mudssky
RUN_MODE = prod
WORK_PATH = /Users/mudssky/coding/gitea

[database]
DB_TYPE = sqlite3
HOST = 127.0.0.1:3306
NAME = gitea
USER = gitea
PASSWD = 
SCHEMA = 
SSL_MODE = disable
CHARSET = utf8
PATH = /Users/mudssky/coding/gitea/data/gitea.db
LOG_SQL = false

[repository]
ROOT = /Users/mudssky/coding/gitea/data/gitea-repositories

[server]
SSH_DOMAIN = localhost
DOMAIN = localhost
HTTP_PORT = 30001
ROOT_URL = http://localhost:30001/
DISABLE_SSH = false
SSH_PORT = 22
LFS_START_SERVER = true
LFS_JWT_SECRET = NB6IE8N3sJVevZJhgyHbRbz-ofu1w77_m_MWcAE4BCA
OFFLINE_MODE = false

[lfs]
PATH = /Users/mudssky/coding/gitea/data/lfs

[mailer]
ENABLED = false

[service]
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
DISABLE_REGISTRATION = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA = false
REQUIRE_SIGNIN_VIEW = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.localhost

[picture]
ENABLE_FEDERATED_AVATAR = false

[openid]
ENABLE_OPENID_SIGNIN = true
ENABLE_OPENID_SIGNUP = true

[session]
PROVIDER = file

[log]
LEVEL = info
ROOT_PATH = /Users/mudssky/coding/gitea/log

[repository.pull-request]
DEFAULT_MERGE_STYLE = merge

[repository.signing]
DEFAULT_TRUST_MODEL = committer

[security]
INSTALL_LOCK = true
INTERNAL_TOKEN = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2NzEwNjkyOTh9.nK1TEpnWxuS2E9hM3P9XNEZIzK9lXBS7hHaYNk9YFqg
PASSWORD_HASH_ALGO = pbkdf2

[migrations]
ALLOW_LOCALNETWORKS = true

[git.timeout]
DEFAULT = 120000
MIGRATE = 120000
MIRROR = 120000
CLONE = 120000
PULL = 120000
GC = 600

[oauth2]
JWT_SECRET = Xvv10mF3KvshVM0ivf_L7VKA2VPjbGNjfCl2Q-azZWk
```

# 确认点

* 是否使用示例中的用户与路径（`/Users/mudssky/coding/gitea`），如需变更请告知目标用户名与根目录。

* 是否保留现有密钥用于迁移；如为新实例则改为重新生成密钥。

* 是否将 `mac-app.ini` 作为独立配置通过 `--config` 指定，或改名为默认 `app.ini`。

