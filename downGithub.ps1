<#
.SYNOPSIS
	A short one-line action-based description, e.g. 'Tests if a function is valid'
.DESCRIPTION
	A longer description of the function, its purpose, common use cases, etc.
.NOTES
	Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
	Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
	Test-MyTestFunction -Verbose
	Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>



[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	$UserName = '',
	# 下载执行的路径
	[string]
	$Path = '.'
)
	
$repos = Invoke-RestMethod -Uri "https://api.github.com/users/$UserName/repos" -Headers @{ "User-Agent" = "Mozilla/5.0" }

$repos

$repoParentPath = Join-Path $Path $UserName

if (-not (Test-Path $repoParentPath)) {
	New-Item -ItemType Directory -Force -Path $repoParentPath
}


foreach ($repo in $repos) {
	$repoName = $repo.name
	$repoUrl = $repo.clone_url
	$repoPath = "$repoParentPath\$repoName"
    
	# 检查是否已经存在该目录，如果不存在则克隆仓库
	if (-not (Test-Path -Path $repoPath)) {
		git clone $repoUrl $repoPath
	}
	else {
		Write-Output "Repository '$repoName' already exists, skipping..."
	}
}



