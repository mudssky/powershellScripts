



function Test-PortOccupation {
	<#
.SYNOPSIS
    检查指定的 TCP 端口是否被占用。

.DESCRIPTION
    此函数用于检查给定的 TCP 端口是否已被其他进程占用。
    这在启动服务前检查端口可用性非常有用，以确保服务能够正常运行。

.PARAMETER Port
    必需参数。要检查的端口号。

.OUTPUTS
    布尔值。如果端口被占用，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-PortOccupation -Port 8080
    检查端口 8080 是否被占用。

.NOTES
    此函数通过 `Get-NetTCPConnection` cmdlet 检查本地 TCP 连接来判断端口占用情况。
    它会忽略状态为 "TimeWait" 的连接，以避免误报。

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

function Get-PortProcess {
	<#
.SYNOPSIS
    获取占用指定 TCP 端口的进程信息。

.DESCRIPTION
    此函数用于获取占用指定 TCP 端口的进程详细信息，包括进程 ID、名称等。
    当需要了解哪个进程占用了特定端口时，此函数非常有用。

.PARAMETER Port
    必需参数。要查询的端口号。

.OUTPUTS
    System.Object。返回包含进程信息的对象，如果端口未被占用则返回 $null。

.EXAMPLE
    Get-PortProcess -Port 8080
    获取占用端口 8080 的进程信息。

.NOTES
    此函数结合使用 `Get-NetTCPConnection` 和 `Get-Process` cmdlet 来获取完整的进程信息。
    它会忽略状态为 "TimeWait" 的连接。

#>

	[CmdletBinding()]
	param (
		[int]$Port
	)
	
	# 获取使用指定端口的TCP连接
	$tcpConnection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "TimeWait" }

	if ($tcpConnection) {
		# 获取进程详细信息
		$process = Get-Process -Id $tcpConnection.OwningProcess -ErrorAction SilentlyContinue
		
		# 创建自定义对象返回进程信息
		$result = [PSCustomObject]@{
			Port = $Port
			ProcessId = $tcpConnection.OwningProcess
			ProcessName = $process.Name
			Path = $process.Path
			CommandLine = $process.CommandLine
		}
		
		return $result
	}
	else {
		return $null
	}
}



function Wait-ForURL {
	<#
.SYNOPSIS
    测试指定的 URL 是否可达。

.DESCRIPTION
    此函数用于等待一个 URL 变得可访问。它会定期尝试连接到指定的 URL，
    直到连接成功或达到设定的超时时间。这在等待服务启动或资源可用时非常有用。

.PARAMETER DevToolsUrl
    必需参数。要等待的 URL。默认为 Chrome DevTools 的 JSON 端点 (`http://localhost:9222/json`)。

.PARAMETER Timeout
    可选参数。等待的最大秒数。如果在此时间内 URL 仍不可达，函数将返回 `$false`。默认为 30 秒。

.PARAMETER Interval
    可选参数。检查 URL 可达性的时间间隔（秒）。默认为 2 秒。

.PARAMETER Verbose
    可选参数。是否输出详细信息。默认为 $false。

.OUTPUTS
    布尔值。如果 URL 在超时时间内可达，则返回 $true；否则返回 $false。

.EXAMPLE
    Wait-ForURL -DevToolsUrl "http://localhost:8080/health" -Timeout 60 -Interval 5
    等待 `http://localhost:8080/health` 在 60 秒内变得可达，每 5 秒检查一次。

.EXAMPLE
    Wait-ForURL -DevToolsUrl "http://localhost:3000" -Verbose $true
    等待 URL 可达并输出详细信息。

.NOTES
    此函数在调试时特别有用，例如等待浏览器 DevTools 地址生效后执行 Web 自动化脚本。
    它使用 `Invoke-RestMethod` 进行 HTTP 请求，并会捕获连接失败时的错误。
    为了确保函数只返回布尔值，默认情况下不输出任何文本信息。

#>
	
	[CmdletBinding()]
	param (
		[string]$DevToolsUrl = "http://localhost:9222/json", # DevTools 协议的 JSON 端点
		[int]$Timeout = 30, # 超时时间（秒）
		[int]$Interval = 2,    # 检查间隔（秒）
		[bool]$ShowOutput = $false # 是否显示输出信息
	)

	# 等待url可访问。可以用于debug时等待浏览器DevTools地址生效。
	# 在vscode preLaunchTask 中设置powershell job，其中可以等待到devtools地址生效后，执行web自动化脚本。

	$startTime = Get-Date

	while ($true) {
		try {
			$response = Invoke-RestMethod -Uri $DevToolsUrl -Method Get -TimeoutSec $Interval
			if ($response) {
				if ($ShowOutput) {
					Write-Host "浏览器已启动并响应 $DevToolsUrl" -ForegroundColor Green
				}
				return $true
			}
		}
		catch {
			# 连接失败时不做任何处理
		}

		$elapsedTime = (Get-Date) - $startTime
		if ($elapsedTime.TotalSeconds -ge $Timeout) {
			if ($ShowOutput) {
				Write-Host "等待超时。$DevToolsUrl 未响应。" -ForegroundColor Yellow
			}
			return $false
		}

		Start-Sleep -Seconds $Interval
	}
}


Export-ModuleMember -Function Test-PortOccupation, Get-PortProcess, Wait-ForURL
