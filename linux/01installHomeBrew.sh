/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# 判断pwsh是否安装
if ! command -v pwsh &> /dev/null
then
    echo "pwsh not found, install it"
    brew install powershell
else
    echo "pwsh found, skip install"
fi
