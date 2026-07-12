# RISEN：Role / Instructions / Steps / End goal / Narrowing

RISEN 适合多步骤任务或强约束交付，强调步骤与收敛条件。

## 适用场景

* 复杂任务需要拆解步骤。
* 输出必须满足严格验收标准。
* 希望模型在生成前先思考流程。

## 结构拆解

* Role：角色与专业能力。
* Instructions：任务总体指令。
* Steps：需要遵循的步骤与顺序。
* End goal：最终交付与验收标准。
* Narrowing：边界、限制、禁止项。

## 模板

```text
Role: {角色/能力}
Instructions: {总体任务}
Steps:
1) {步骤一}
2) {步骤二}
3) {步骤三}
End goal: {最终交付 + 验收标准}
Narrowing: {限制/禁止项/依赖}
```

## 示例

```text
Role: 你是资深解决方案架构师。
Instructions: 生成一份系统改造方案。
Steps:
1) 归纳现有系统问题与风险。
2) 提出 2-3 个改造方案并对比。
3) 给出推荐方案与落地计划。
End goal: 输出结构化方案，包含范围、成本、风险与里程碑。
Narrowing: 不要引用外部链接，所有建议基于提供的背景描述。
```

## 注意事项

* Steps 是核心，确保每一步都可产出具体内容。
* Narrowing 建议写“可验证的约束”，如长度、格式、禁止项。
