
param(
    # [Parameter(Mandatory=$true)][int]$startNum,
    # [int]$endNum=$startNum
    [string]$path = '.'
)
# 由相对路径获取绝对路径
$path = (Resolve-Path $path).path
$spiderPath = 'D:\coding\Projects\python\python3Spiders\dlsiteSpider'
# Write-Host -ForegroundColor Red $path

if (-not (Test-Path $spiderPath)) {
    Write-Host -ForegroundColor red ('{} is not exist' -f $spiderPath)
    Exit 1
}
Set-Location $spiderPath
Invoke-Expression (pdm venv activate)
python .\updateOwnedProduct.py main $path


