function Get-SnippetsBody {
	[CmdletBinding()]
	param (
		
	)
	
	begin {
		
	}
	
	process {
		$bodyList = (Get-Clipboard ).Split('\n') | ForEach-Object { '"' + $_ + '"' }
		$bodyList
		Set-Clipboard -Value ($bodyList -join ',') 

	}
	
	end {
		
	}
}



Get-SnippetsBody