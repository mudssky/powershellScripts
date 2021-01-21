
param(
    [string]$targerItem
)

$startUpFolder = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

Copy-Item $targerItem $startUpFolder

Write-Host -ForegroundColor Green ('write  item: {0} to folder {1}' -f $targerItem,$startUpFolder)