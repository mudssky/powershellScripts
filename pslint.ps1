
Param(
	[string]$Path = '.',
	[string]$ConfigPath = "$PSScriptRoot\.vscode\analyzersettings.psd1",
	[switch]$Install
)

if ($Install) {
	Install-Module PSScriptAnalyzer
	exit
}



Invoke-ScriptAnalyzer -Recurse -Path  . -Profile $ConfigPath