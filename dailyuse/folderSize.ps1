﻿$folderSize=0;ls -Recurse |   foreach{ $folderSize+=$_.length};$folderSize/1gb