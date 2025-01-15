function Convert-DoubleQuotes {
	param (
		[string]$inputString
	)

	# 使用 -replace 运算符替换双引号为转义的双引号
	return $inputString -replace '"', '\"'
}

function Get-SnippetsBody {
	[CmdletBinding()]
	param (
		
	)
	
	begin {
		
	}
	
	process {

		$bodyList = (Get-Clipboard ).Split('\n') | ForEach-Object { '"' + (Convert-DoubleQuotes -inputString $_) + '"' }
		$res = $bodyList -join ','
		$res
		Set-Clipboard -Value $res

	}
	
	end {
		
	}
}



Get-SnippetsBody