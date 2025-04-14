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


foreach ($repo in $finalRepos) {
	$repoName = $repo.name
	$repoUrl = $repo.clone_url
	$repoPath = "$repoParentPath\$repoName"
    
	# 检查是否已经存在该目录
	if (-not (Test-Path -Path $repoPath)) {
		gh repo clone $repoUrl $repoPath -- --mirror
	}
	else {
		Write-Output "Repository '$repoName' already exists, updating..."
		Push-Location $repoPath
		try {
			git fetch --all
			git remote update
		}
		finally {
			Pop-Location
		}
	}
}



