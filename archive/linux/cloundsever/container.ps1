# 这个脚本记录云服务器上值得启动的服务

# 远程控制
# rusrdesk
Write-Host "正在启动 rustdesk 服务..."
start-container.ps1 -ServiceName rustdesk

# oss
Write-Host "正在启动 rustfs oss 服务..."
$DefaultPassword = Read-Host -AsSecureString -Prompt "请输入默认密码"
start-container.ps1 -ServiceName rustfs -DefaultPassword $DefaultPassword

# 向量数据库
Write-Host "正在启动qdrant向量数据库 服务..."
start-container.ps1 -ServiceName qdrant

# 数据库
Write-Host "正在启动postgre数据库 服务..."
start-container.ps1 -ServiceName postgres

# 监控
Write-Host "正在启动 beszel 监控服务..."
start-container.ps1 -ServiceName beszel

