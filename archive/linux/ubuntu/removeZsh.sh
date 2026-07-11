# 如果存在，调用删除
if [ -f ~/.zshrc ]; then
  rm ~/.zshrc
  echo "~/.zshrc has been deleted."
fi
# 如果~/.oh-my-zsh
if [ -d ~/.oh-my-zsh ]; then
  rm -rf ~/.oh-my-zsh
  echo "~/.oh-my-zsh has been deleted."
fi


