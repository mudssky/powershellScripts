param(
	[CmdletBinding()]
	[string]$Path = '.'
)

trap {
	"error found"
}

Get-ChildItem -Recurse -Path $Path  -Filter *.ipynb | ForEach-Object { jupytext --set-formats 'ipynb,py:percent' $_.FullName }