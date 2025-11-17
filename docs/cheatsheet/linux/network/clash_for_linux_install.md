**简介**
- 一键安装基于 `clash/mihomo` 的代理环境，默认安装 `mihomo` 内核，支持使用 `subconverter` 进行本地订阅转换。
- 适配多架构与主流发行版：`CentOS 7.6`、`Debian 12`、`Ubuntu 24.04.1 LTS`。
- 提供开箱即用的 `clashctl` 命令集，支持系统代理、Tun 模式、Mixin 配置、订阅更新等。

**环境要求**
- 用户权限：`root` 或 `sudo` 用户。
- Shell 支持：`bash`、`zsh`、`fish`。

**一键安装**
- `git clone --branch master --depth 1 https://gh-proxy.com/https://github.com/nelvko/clash-for-linux-install.git && cd clash-for-linux-install && sudo bash install.sh`
- 默认通过远程订阅获取配置进行安装；本地配置安装可参考项目说明。

**命令一览（clashctl）**
- `clashctl on` 开启代理（别名 `clashon`）
- `clashctl off` 关闭代理（别名 `clashoff`）
- `clashctl ui` 打印面板地址
- `clashctl status` 查看内核状态
- `clashctl proxy on|off` 控制系统代理
- `clashctl tun on|off` 开启/关闭 Tun 模式
- `clashctl mixin -e|-r` 编辑/查看 Mixin 与运行时配置
- `clashctl secret [SECRET]` 设置或查看 Web 控制台密钥
- `clashctl update [auto|log] [url]` 更新订阅、设置定时或查看更新日志

**优雅启停**
- `clashon` 与 `clashoff` 在启停内核的同时自动设置系统代理。
- 仅控制系统代理：`clashproxy on|off`。

**Web 控制台**
- 打印地址：`clashui`
- 放行端口：`9090`
- 设置密钥：`clashsecret 666`；查看密钥：`clashsecret`
- 暴露到公网时建议定期更换密钥。

**更新订阅**
- 立即更新：`clashupdate https://example.com`
- 定时更新：`clashupdate auto [url]`（使用 `crontab -e` 可调整频率与链接）
- 查看日志：`clashupdate log`
- 会记住上次成功的订阅链接，后续可直接执行 `clashupdate`。

**Tun 模式**
- 查看状态：`clashtun`
- 开启：`clashtun on`
- 作用：将本机与容器（如 Docker）的所有流量路由到 `clash` 代理，并进行 DNS 劫持等。
- 参考与注意事项：基于 `clash-verge-rev`、`clash.wiki`，使用前请阅读项目内注意事项。

**Mixin 配置**
- 查看 Mixin：`clashmixin`
- 编辑 Mixin：`clashmixin -e`
- 查看运行时配置：`clashmixin -r`
- 持久化方式：将自定义项写入 `mixin.yaml`，避免订阅更新后丢失。
- 加载机制：启动时使用 `runtime.yaml`（订阅配置 `config.yaml` 与 Mixin 合并），相同配置项以 Mixin 为准。
- 重要提示：直接修改 `config.yaml` 并不会生效。

**卸载**
- `sudo bash uninstall.sh`

**参考与关联工具**
- Web 控制台：`yacd`
- 订阅转换：`subconverter`
- YAML 处理：`yq`