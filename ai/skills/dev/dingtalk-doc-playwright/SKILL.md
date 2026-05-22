---
name: dingtalk-doc-playwright
description: 使用 Playwright 自动编辑钉钉文档，包括写入 Markdown/正文、定位钉钉文档 iframe、处理虚拟滚动、上传截图并校验保存状态。Use when 用户要求在钉钉文档/阿里文档里写说明、插入截图、修正文档内容，或提到 alidocs.dingtalk.com、钉钉文档、DingTalk docs。
---

# 钉钉文档 Playwright 操作

## 适用范围

用于“浏览器已经能访问目标钉钉文档”之后的编辑动作。不包含浏览器连接、登录、扩展授权流程。

## 快速流程

1. 打开或切到目标文档页，确认页面里有 `#wiki-doc-iframe`。
2. 点击文档里的“编辑”，等待 iframe URL 包含 `/note/edit`。
3. 写正文时优先粘贴 Markdown。钉钉文档可识别 Markdown，比纯文本编号更容易保留标题和列表结构。
4. 插图不要依赖系统图片剪贴板，优先用 Playwright `drop --path=...` 拖放本地图片文件。
5. 文档是虚拟滚动，不能只用 `window.scrollTo`。内部滚动容器通常是 `#layout_body`。
6. 完成后校验“已保存”、关键标题、占位文字和图片数量。

## 常用命令

```powershell
playwright-cli -s=docs snapshot --depth=8
playwright-cli -s=docs run-code --filename="$env:USERPROFILE\.agents\skills\dingtalk-doc-playwright\scripts\inspect-doc.js"
playwright-cli -s=docs drop "<ref-or-selector>" --path="C:\path\to\screenshot.png"
```

## 写入正文

优先把 Markdown 放进剪贴板，再点击正文区域，执行 `Ctrl+A` 和 `Ctrl+V`。

注意：钉钉编辑器有隐藏输入层。外层 snapshot 里可能还会看到旧文字或隐藏 textbox，不能只凭这个判断失败。应使用 `scripts/inspect-doc.js` 读取 `/note/edit` iframe 的正文文本和保存状态。

## 插入图片

推荐先在正文里写稳定占位行，例如：

```md
截图：设置页面
```

然后用占位文本定位并拖放图片：

```powershell
playwright-cli -s=docs run-code --filename="$env:USERPROFILE\.agents\skills\dingtalk-doc-playwright\scripts\drop-image-after-placeholder.js"
```

脚本默认通过环境变量传参：

```powershell
$env:DINGTALK_PLACEHOLDER='截图：设置页面'
$env:DINGTALK_IMAGE_PATH='C:\path\to\settings.png'
playwright-cli -s=docs run-code --filename="$env:USERPROFILE\.agents\skills\dingtalk-doc-playwright\scripts\drop-image-after-placeholder.js"
```

## 修正错图

1. 用 `scripts/find-placeholder.js` 滚动到占位行附近。
2. 点击占位行下方的大图，按 `Delete` 删除。`Backspace` 不一定生效。
3. 再用 `drop-image-after-placeholder.js` 上传正确图片。
4. 用 `verify-doc.js` 校验图片数量和关键占位。

## 避坑清单

- 不要用系统剪贴板直接 `SetImage()` 后 `Ctrl+V` 粘图片，钉钉文档可能不识别。
- 不要用截图文件名判断内容正确，先切到目标页面再截图；本次踩过“设置截图实际截成 Excel 页面”的坑。
- 不要只看外层页面文本，正文在 iframe 里，且存在隐藏输入层。
- 不要假设滚动是 `window`；钉钉文档正文滚动多半在 `#layout_body`。
- 上传图片后 DOM ref 会失效，需要重新 snapshot 或重新按文本定位。
- 校验图片去重时不要截断 URL 前缀，钉钉资源 URL 前缀高度相似。

