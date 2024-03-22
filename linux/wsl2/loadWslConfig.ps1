


Copy-Item -Force $PSScriptRoot/.wslconfig $env:USERPROFILE/.wslconfig
# 复制配置后需要重启wsl生效

wsl --shutdown