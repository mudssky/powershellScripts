



function Test-PortOccupation {
	<#
.SYNOPSIS
	check if a port is occupied
.DESCRIPTION
	check if a port is occupied,we can check it before we start a service to ensure service is running 
	on correct port
.NOTES
	Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
	Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
	Test-MyTestFunction -Verbose
	Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>

	[CmdletBinding()]
	param (
		[int]$Port
	)
	# 检查端口占用情况
	# 获取使用指定端口的TCP连接
	$tcpConnection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "TimeWait" }

	if ($tcpConnection) {
		return $true
	}
	else {
		return $false
	}
}



function Wait-ForURL {
	<#
	.SYNOPSIS
		test if a url is reachable

	.DESCRIPTION
		test if a url is reachable,we can use this function to wait for a service to start
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
	#>
	
	
	param (
		[string]$DevToolsUrl = "http://localhost:9222/json", # DevTools 协议的 JSON 端点
		[int]$Timeout = 30, # 超时时间（秒）
		[int]$Interval = 2    # 检查间隔（秒）
	)

	# 等待url可访问。可以用于debug时等待浏览器DevTools地址生效。
	# 在vscode preLaunchTask 中设置powershell job，其中可以等待到devtools地址生效后，执行web自动化脚本。

	$startTime = Get-Date

	while ($true) {
		try {
			$response = Invoke-RestMethod -Uri $DevToolsUrl -Method Get -TimeoutSec $Interval
			if ($response) {
				Write-Output "浏览器已启动并响应 $DevToolsUrl"
				return $true
			}
		}
		catch {
			# 连接失败时不做任何处理
		}

		$elapsedTime = (Get-Date) - $startTime
		if ($elapsedTime.TotalSeconds -ge $Timeout) {
			Write-Output "等待超时。$DevtoolsUrl 未响应。"
			return $false
		}

		Start-Sleep -Seconds $Interval
	}
}


Export-ModuleMember -Function *
