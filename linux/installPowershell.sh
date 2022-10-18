#!/usr/bin/env bash

if command -v git >/dev/null 2>&1; then 
  echo 'powershell 已安装' 

fi

powershellUrl='https://github.com/PowerShell/PowerShell/releases/download/v7.2.6/powershell-7.2.6-linux-arm64.tar.gz'

myfolder='/etc/mudssky/tools'
powershellFolder=$myfolder/powershell
mkdir -p $myfolder
mkdir -p $powershellFolder

wget -c $powershellUrl -P $powershellFolder

powershellGz="$powershellFolder/powershell-7.2.6-linux-arm64.tar.gz"
tar -xf  $powershellGz  --directory $powershellFolder
rm $powershellGz

echo ( 'export PATH=$PATH:'${powershellFolder} )>> ~/.profile

source ~/.profile