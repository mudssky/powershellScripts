$internetSettingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"


function Close-Proxy() {
	# 关闭代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 0
}


function Start-Proxy() {
	param(
	
		[string]$URL = 'http://127.0.0.1:8080',
		[string]$username,
		[SecureString]$password
	)
	
	Set-ItemProperty -Path $internetSettingPath -Name ProxyServer -Value $URL
	if ($username -and $password) {
		Set-ItemProperty -Path $internetSettingPath -Name ProxyUser  -Value $username
		Set-ItemProperty -Path $internetSettingPath -Name ProxyPass  -Value $password
	}

	# 启用代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 1
	# 重启windows代理自动检测服务，使其生效
	# Restart-Service -Name WinHttpAutoProxySvc
}
