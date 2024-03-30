# lsp 安装
# 执行下面的命令查看安装的lsp
#  hx --health 


# 前端必备
# css
npm i -g vscode-langservers-extracted
# vue
npm i -g @vue/language-server
npm i -g prettier

# typescript
npm install -g typescript typescript-language-server

# prisma
npm install -g @prisma/language-server
# bash
npm i -g bash-language-server
# docker
npm install -g dockerfile-language-server-nodejs

# python
pip install -U 'python-lsp-server[all]'

# yarml
npm i -g yaml-language-server@next
# go 
# go相关的安装vscode插件时就顺便安装了
# go install golang.org/x/tools/gopls@latest          # LSP
# go install github.com/go-delve/delve/cmd/dlv@latest # Debugger
# go install golang.org/x/tools/cmd/goimports@latest  # Formatter