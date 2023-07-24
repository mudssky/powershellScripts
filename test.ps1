13..64 | ForEach-Object { $num3 = ('{0:D3}' -f $_); 
	$filterStr = ('*{0}*' -f $num3); 
	$file = (Get-ChildItem  $filterStr)[0];
	if ($file) {
		Rename-Item  -Path $file.Name -NewName $file.Name.Replace($num3, $_ + 104 + '');
	}
  
}


