# Prompt 保存格式（Prompty、POML 等）

Prompt 保存格式的目标是：**可读、可复用、可版本化、可追溯**。建议将 Prompt 视为“配置 + 模板”，用结构化元数据管理，正文部分保留可读性。

## 通用字段建议

* prompt_id / name：稳定标识。
* version：版本号与变更记录。
* description：用途、场景与限制。
* inputs / variables：输入变量与类型。
* outputs / schema：输出结构或校验规则。
* model / parameters：模型选择、温度、top_p 等。
* tags / owner：分类与负责人。
* tests / examples：回归样例或示例输出。

## Prompty（YAML Front Matter + Prompt 正文）

Prompty 常用 YAML 作为元数据区，正文部分用 Markdown/纯文本描述 Prompt，变量以模板语法占位。

```text
---
name: summarize_email
version: 1.0.0
description: 对邮件进行摘要
inputs:
  email_text:
    type: string
model:
  parameters:
    temperature: 0.2
---

# System
你是资深客服助理，擅长提炼关键信息。

# User
请用 3 条要点总结以下邮件：
{{email_text}}
```

适合需要**清晰元数据 + 方便协作编辑**的团队场景。

## POML（Prompt Markup Language）

POML 往往采用类似 XML 的标签来组织 Prompt 结构，便于模块化与后期解析。标签集合可按团队约定扩展。

```text
<prompt>
  <role>你是资深数据分析师</role>
  <context>{{context}}</context>
  <task>找出异常值并解释原因</task>
  <output format="markdown">表格 + 结论</output>
</prompt>
```

适合需要**结构化编排与自动化处理**的场景，例如生成多角色、多段落 Prompt。

## 其他常见保存方式

* Markdown + Front Matter：与 Prompty 类似，但不限定字段，可快速落地。
* YAML/JSON + 模板文件：元数据与正文分离，便于程序化加载与渲染。
* 代码内模板（如 Mustache/Jinja2）：适合与业务逻辑强耦合的应用。

## 使用建议

* 元数据与正文分离，便于版本与回滚。
* 统一变量命名规范（如 snake_case）并提供样例值。
* 把格式校验（JSON Schema/正则）作为 Prompt 的一部分管理。
* 避免在 Prompt 文件中写入敏感信息。
