$num=0;ls -Force -Recurse |foreach{$num++; if ($_.Name.EndsWith('.torrent')){"clean : $($_.FullName)";del -Force -LiteralPath $_.FullName}} ; "fileCounts:$num"

$urlnum=0;ls -Force -Recurse |foreach{$num++; if ($_.Name.EndsWith('.url')){"clean : $($_.FullName)";del -Force -LiteralPath $_.FullName}} ; "fileCounts:$urlnum";pause