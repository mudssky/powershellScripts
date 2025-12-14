为 apps-config.json 中的 12 个指定工具添加 `tag` 数组，并标记为 `linuxserver`：

**需要修改的工具**：
1. jq - JSON 处理工具
2. ripgrep - 快速文本搜索
3. fd - 文件搜索工具
4. eza - 现代 ls 替代品
5. bat - cat 替代品
6. fzf - 模糊查找工具
7. zoxide - 智能目录跳转
8. starship - shell 提示符
9. fnm - Node.js 版本管理
10. pyenv - Python 版本管理
11. neovim - 现代化编辑器
12. lazygit - Git TUI 界面

**修改方式**：
在每个工具的对象中添加 `"tag": ["linuxserver"]` 字段，保持其他字段不变。

**验证**：
修改完成后验证 JSON 格式正确性。