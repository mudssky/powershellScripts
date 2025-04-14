<#
.SYNOPSIS
    批量下载指定 GitHub 用户的所有仓库。

.DESCRIPTION
    此脚本用于下载指定 GitHub 用户的所有公开仓库。
    可以选择是否在文件夹名称中包含日期。

.PARAMETER UserName
    GitHub 用户名（必填）

.PARAMETER Path
    下载仓库的本地路径，默认为当前目录

.PARAMETER WithDate
    是否在文件夹名称中包含日期

.EXAMPLE
    .\downGithub.ps1 -UserName "octocat"
    下载用户 octocat 的所有仓库到当前目录

.EXAMPLE
    .\downGithub.ps1 -UserName "octocat" -Path "D:\GitRepos" -WithDate
    下载用户 octocat 的所有仓库到 D:\GitRepos，并在文件夹名称中包含日期
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	$UserName = '',
	# 下载执行的路径
	[string]
	$Path = '.',
	[switch]
	$WithDate
	# 纯备份场景不需要工作区
	# [switch]
	# $OnlyBackup
)
	
# $repos = Invoke-RestMethod -Uri "https://api.github.com/users/$UserName/repos" -Headers @{ "User-Agent" = "Mozilla/5.0" }
# gh命令返回的信息更多更全
$ghRepos = gh repo list $UserName --json 'name,url,sshUrl' --limit 1000 --source | ConvertFrom-Json
# gh repo list --json
# Specify one or more comma-separated fields for `--json`:
#   assignableUsers
#   codeOfConduct
#   contactLinks
#   createdAt
#   defaultBranchRef
#   deleteBranchOnMerge
#   description
#   diskUsage
#   forkCount
#   fundingLinks
#   hasIssuesEnabled
#   hasProjectsEnabled
#   hasWikiEnabled
#   homepageUrl
#   id
#   isArchived
#   isBlankIssuesEnabled
#   isEmpty
#   isFork
#   isInOrganization
#   isMirror
#   isPrivate
#   isSecurityPolicyEnabled
#   isTemplate
#   isUserConfigurationRepository
#   issueTemplates
#   issues
#   labels
#   languages
#   latestRelease
#   licenseInfo
#   mentionableUsers
#   mergeCommitAllowed
#   milestones
#   mirrorUrl
#   name
#   nameWithOwner
#   openGraphImageUrl
#   owner
#   parent
#   primaryLanguage
#   projects
#   pullRequestTemplates
#   pullRequests
#   pushedAt
#   rebaseMergeAllowed
#   repositoryTopics
#   securityPolicyUrl
#   squashMergeAllowed
#   sshUrl
#   stargazerCount
#   templateRepository
#   updatedAt
#   url
#   usesCustomOpenGraphImage
#   viewerCanAdminister
#   viewerDefaultCommitEmail
#   viewerDefaultMergeMethod
#   viewerHasStarred
#   viewerPermission
#   viewerPossibleCommitEmails
#   viewerSubscription
#   watchers
$finalRepos = $ghRepos | ForEach-Object {
	# 创建新对象并添加必要的属性
	[PSCustomObject]@{
		name      = $_.name
		clone_url = $_.url
	}
}

$finalRepos

$folderMame = $UserName

if ($WithDate) {
	$dateString = Get-Date -Format "yyyyMMdd"
	$folderMame = "$dateString-$UserName"
}


$repoParentPath = Join-Path $Path $folderMame

if (-not (Test-Path $repoParentPath)) {
	New-Item -ItemType Directory -Force -Path $repoParentPath
}
function updateRepo {
	param(
		[string]$Path
	)
	# 检查是否为 Git 仓库
	if (-not (Test-Path (Join-Path $Path ".git"))) {
		Write-Error "目录 '$Path' 不是 Git 仓库！"
		return
	}
	try {
		# 使用 -C 直接指定路径，避免切换目录
		git -C $Path fetch --all --prune
		Write-Host "仓库 '$Path' 更新成功。" -ForegroundColor Green
	}
	catch {
		Write-Error "更新仓库 '$Path' 时出错: $_"
	}
	# Push-Location $Path
	# try {
	# 	git fetch --all
	# 	git remote update
	# }
	# finally {
	# 	Pop-Location
	# }
}

$totalRepos = $finalRepos.Count
$currentRepo = 0

foreach ($repo in $finalRepos) {
	$currentRepo++
	$repoName = $repo.name
	$repoUrl = $repo.clone_url
	$repoPath = "$repoParentPath\$repoName"
    
	# 显示进度
	Write-Progress -Activity "正在处理仓库" -Status "$currentRepo/$totalRepos - $repoName" `
		-PercentComplete (($currentRepo / $totalRepos) * 100) `
		-CurrentOperation "正在下载/更新仓库"
    
	# 检查是否已经存在该目录
	if (-not (Test-Path -Path $repoPath)) {
		gh repo clone $repoUrl $repoPath
		updateRepo -Path $repoPath
	}
	else {
		Write-Output "Repository '$repoName' already exists, updating..."
		updateRepo -Path $repoPath
	}
}

# 完成后清除进度条
Write-Progress -Activity "完成" -Completed



