<#
.synopsis
递归遍历子目录，运用ffmpeg进行格式转换
.example
conventAllbyExt -inputExt tta -outputExt flac -deleteSource $false
#>

param(
    [Parameter(Mandatory = $True)][string]$inputExt,
    [Parameter(Mandatory = $True)][string]$outputExt,
    [bool] $deleteSource = $true
)
$inputExtCounts = 0
Get-ChildItem -Recurse -Force | 
ForEach-Object { if ($_.name.EndsWith('.' + $inputExt)) {
        $inputExtCounts++; ffmpeg -i $_.FullName  ($_.FullName.TrimEnd($inputExt) + $outputExt); if ($deleteSource) {
            Remove-Item -Force -LiteralPath $_.FullName; "convert and deleted: $($_.Fullname)"
        }
    }
}

Write-Host -ForegroundColor Green  "$inputExt counts:$inputExtCounts"; pause