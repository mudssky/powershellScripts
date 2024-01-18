
Param(
	[string]$Path = '.',
	[string]$ConfigPath = "$PSScriptRoot\.vscode\analyzersettings.psd1"
)



Invoke-ScriptAnalyzer -Path  . -Profile $ConfigPath