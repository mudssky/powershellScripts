---
name: repo-ops
description: Use when 用户要求在本仓库增加、修改或审查 PowerShell、Bash、Zsh profile 的 CLI 初始化、补全、历史、提示符、键位、延迟加载或相关安装清单。
---

# 仓库工程操作

## 工作流

1. 先确认请求是否匹配已有 reference；匹配时必须读取对应文档，没有匹配流程时按当前仓库 Trellis spec 执行，不预造空 reference。
2. Shell Profile 与相关 CLI 安装请求读取 [Shell Profile 集成流程](references/shell-profile-integration.md)。
3. 所有路径、包名、加载行为和验证命令以当前仓库代码、清单、spec 与测试为事实来源，不在 Skill 复制第二份产品实现。
4. 非平凡改动必须执行目标路径 smoke、专项测试和仓库门禁；验证失败时修复源头，不放宽断言或隐藏错误。

## 完成条件

- 已读取并遵守匹配 reference 与相关 Trellis spec。
- 代码、清单、测试和文档不存在第二套事实来源。
- 已验证用户实际入口、失败降级和重复执行行为。
- 未修改用户完整 rc、账号、密钥或同步配置，除非任务明确批准。

## 反模式

- 为尚无真实需求的仓库操作创建空 reference 或占位流程。
- 把具体工具包名、生成脚本或产品实现复制进 Skill。
- 只运行静态检查，不执行受影响的真实入口 smoke。
- 保留旧 Skill alias、转发入口或重复触发描述。
