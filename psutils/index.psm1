# Import-Module -Name $PSScriptRoot\test.psm1
# Import-Module -Name $PSScriptRoot\functions.psm1


# 批量导入modules目录下的模块
Get-ChildItem  $PSScriptRoot/modules/*.psm1 | ForEach-Object {
	Import-Module -Name $_.FullName
}


