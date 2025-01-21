function Convert-DoubleQuotes {
	param (
		[string]$inputString
	)

	# 使用 -replace 运算符替换双引号为转义的双引号
	return $inputString -replace '"', '\"'
}

Import-Module (Resolve-Path -Path $PSScriptRoot/psutils)

function Get-SnippetsBody {
	[CmdletBinding()]
	param (
		
	)
	
	begin {
		
	}
	
	process {

		$content = Get-Clipboard -Raw
		$lineBreak = Get-LineBreak -Content $content -Debug

		$bodyList = ($content ).Split($lineBreak) | ForEach-Object { '"' + (Convert-DoubleQuotes -inputString $_) + '"' }
		$res = $bodyList -join (',' + $lineBreak)
		$res
		Set-Clipboard -Value $res

	}
	
	end {
		
	}
}



Get-SnippetsBody