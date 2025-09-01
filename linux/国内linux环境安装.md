## 1.换源

使用chsrc项目可以换各种系统源和软件源

https://github.com/RubyMetric/chsrc

```
curl -LO https://gitee.com/RubyMetric/chsrc/releases/download/pre/chsrc_latest-1_amd64.deb
sudo apt install ./chsrc_latest-1_amd64.deb
```





## 2.安装homebrew

可以用清华的homebrew源安装

https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/

在终端输入以下几行命令设置环境变量：

```
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_INSTALL_FROM_API=1
# export HOMEBREW_API_DOMAIN
# export HOMEBREW_BOTTLE_DOMAIN
# export HOMEBREW_PIP_INDEX_URL
```

在终端运行以下命令以安装 Homebrew / Linuxbrew

```
# 从镜像下载安装脚本并安装 Homebrew / Linuxbrew
git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git brew-install
/bin/bash brew-install/install.sh
rm -rf brew-install

# 也可从 GitHub 获取官方安装脚本安装 Homebrew / Linuxbrew
/bin/bash -c "$(curl -fsSL https://github.com/Homebrew/install/raw/master/install.sh)"
```

## 3.node环境安装

使用homebrew 安装fnm

```
brew install fnm
# 安装后需要peizhishell
# 在 ~/.bashrc中添加下面这行
# eval "$(fnm env --use-on-cd --shell bash)"
# 之后 source ~/.bashrc
fnm install 22
fnm use 22

```

