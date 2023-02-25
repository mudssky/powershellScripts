param(
	[CmdletBinding()]
	[string]$Path = '.'
)


Get-ChildItem -Recurse -Path $Path  -Filter *.ipynb | ForEach-Object { jupytext --set-formats ipynb, py:percent $_.FullName }