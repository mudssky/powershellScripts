
[CmdletBinding()]
param (
	[ValidateSet('git', 'npm')]
	[string]
	$SetProxyProgram = '',
	[ValidateSet('git', 'npm')]
	$UnsetProxyProgram = ''
)

switch ($SetProxyProgram) {
	'git' {
		git config --global http.https://github.com.proxy $env:http_proxy
		git config --global https.https://github.com.proxy $env:https_proxy
	}
	Default {}
}