﻿$num=0;ls -Recurse -Force |foreach{$num++; if ($_.Name.EndsWith('.torrent')){"clean : $($_.FullName)";del  -Force -LiteralPath $_.FullName}} ; "fileCounts:$num";pause