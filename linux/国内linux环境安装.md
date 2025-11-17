## 1.换源

使用chsrc项目可以换各种系统源和软件源

<https://github.com/RubyMetric/chsrc>

```
curl -LO https://gitee.com/RubyMetric/chsrc/releases/download/pre/chsrc_latest-1_amd64.deb
sudo apt install ./chsrc_latest-1_amd64.deb
```

## 2.安装homebrew

可以用清华的homebrew源安装

<https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/>

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

## 4. docker安装

可以用官网的安装脚本

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
# sudo sh get-docker.sh
# 指定国内镜像安装
sudo sh ./get-docker.sh --mirror Aliyun  
```

### docker镜像配置

docker容器也要配置镜像源,或者你也可以准备好一个配置好的容器，到时候直接拉取

#### linux容器换源

下面演示的是更换清华镜像源

```dockerfile
ARG APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn
ARG APT_SECURITY_MIRROR=https://mirrors.tuna.tsinghua.edu.cn
# 换源操作
RUN set -eux; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    echo "配置APT镜像源..."; \
    if [ -f /etc/apt/sources.list ]; then \
      cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
    fi; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      mv /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak; \
    fi; \
    cat > /etc/apt/sources.list <<EOF
deb ${APT_MIRROR}/debian/ ${codename} main contrib non-free non-free-firmware
deb-src ${APT_MIRROR}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${APT_SECURITY_MIRROR}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
deb ${APT_MIRROR}/debian/ ${codename}-updates main contrib non-free non-free-firmware
EOF
```

#### uv 换源

uv 安装,uv使用官方的安装脚本也会下载不下来

```dockerfile
# 通过清华 TUNA PyPI 镜像安装 uv（官方支持从 PyPI 安装）
RUN python -m pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple uv

```

通过环境变量配置uv下载时的源地址

```
# 配置 uv 默认索引与下载容错
ENV UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple \
    UV_HTTP_TIMEOUT=60 \
    UV_HTTP_RETRIES=5 \
    UV_CACHE_DIR=/app/.cache/uv
```

#### ai换源prompt

参考这个文档，给dockerfile换源
