
param(
# [Parameter(Mandatory=$true)][int]$startNum,
# [int]$endNum=$startNum
[string]$path='.'
)
# 由相对路径获取绝对路径
$path = (Resolve-Path $path).path
# Write-Host -ForegroundColor Red $path
if (-not (Test-Path 'D:\code\Projects\python3Spiders\dlsiteSpider')){
    Write-Host -ForegroundColor red 'D:\code\Projects\python3Spiders\dlsiteSpider is not exist'
}else{
Set-Location 'D:\code\Projects\python3Spiders\dlsiteSpider'
        python .\updateOwnedProduct.py main $path
}


