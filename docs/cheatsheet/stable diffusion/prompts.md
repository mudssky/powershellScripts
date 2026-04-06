# Stable Diffusion AI 绘图提示词Cheatsheet

## 📝 一、核心理念：从想法到图像

核心任务是将你脑海中的画面，用精准、结构化的语言描述给AI。公式越清晰，画面越接近你的想象。

---

## 🏛️ 二、提示词黄金公式 (Prompt Formula)

一个高质量的提示词通常遵循以下结构，重要性从左到右递减：

`[主体] + [核心细节:动作/服装/表情] + [艺术风格] + [构图/视角] + [光照/氛围] + [质量/画质词]`

---

## 🧩 三、核心要素拆解 (Core Elements)

| 类别 | 英文关键词 | 中文说明 |
| :--- | :--- | :--- |
| **主体 (Subject)** | `1girl, handsome man, dragon, castle` | 你想画的核心内容，越具体越好 |
| **细节 (Details)** | `wearing red dress, smiling, intricate armor` | 主体的特征、动作、服装、表情等 |
| **风格 (Style)** | `anime style, oil painting, photorealistic` | 艺术风格，决定了画面的整体观感 |
| **构图 (Composition)** | `close-up, full body shot, from above` | 画面如何布局，主体在什么位置 |
| **光照 (Lighting)** | `cinematic lighting, golden hour, neon lights` | 光线效果，是氛围和质感的关键 |
| **氛围 (Atmosphere)** | `epic, romantic, mysterious, dark fantasy` | 画面传达的情绪和感觉 |
| **画质 (Quality)** | `masterpiece, best quality, 8k, ultra-detailed` | 提升画面最终质量和细节的词 |

---

## 🚀 四、高级语法：提示词融合 (Prompt Fusion)

这是控制AI如何“思考”和“组合”概念的关键，能创造出更精确、更具创意的图像。

### **1. 权重控制 (Weight Control)**

用于增强或减弱某个关键词的影响力。

- **增强权重**:
  - `(word:1.3)` - 将 "word" 的重要性提升30%。数值越高，影响越大。
  - `{word}` / `((word))` - 快捷增强，约等于 `(word:1.1)` / `(word:1.21)`。

- **降低权重**:
  - `(word:0.7)` - 将 "word" 的重要性降低30%。
  - `[word]` / `[[word]]` - 快捷减弱，约等于 `(word:0.9)` / `(word:0.81)`。

**使用场景**:

```text
(masterpiece:1.2), beautiful girl, (red dress:1.4), [forest background:0.7]
// 重点突出“杰作”和“红裙”，同时弱化“森林背景”
```

### **2. 概念交替/混合 (Concept Alternating/Blending)**

在生成过程的每一步交替使用不同的概念，从而实现无缝融合。

- **语法**: `[word1|word2]`

**使用场景**:

- **生物混合**: `a [cat|dog] hybrid` - 生成一只同时具备猫和狗特征的生物。
- **风格融合**: `a portrait in [oil painting|watercolor] style` - 创造一种介于油画和水彩之间的独特质感。
- **特征融合**: `girl with [red|blue] eyes` - 眼睛可能呈现出红蓝混合的紫色，或两只眼睛颜色不同。

### **3. 概念渐变/调度 (Concept Transition/Scheduling)**

在生成过程的特定步骤后，从一个概念切换到另一个。

- **语法**: `[from:to:when]`
- `from`: 初始概念
- `to`: 目标概念
- `when`: 切换时机。可以是0到1的小数（代表总步数的百分比），也可以是整数（代表具体步数）。

**使用场景**:

- **概念替换**: `[a photo of a flower:a photo of a skull:0.5]` - 画面一开始是花，生成到一半时（50%的步数后），AI会开始转向绘制骷髅，最终产生花与骷髅的融合形态。
- **细节修正**: `[scary monster:cute monster:0.3]` - 开头让AI自由发挥画一个恐怖怪物，在30%的步数后，引导它向“可爱”的方向修正。

### **4. 组合使用 (Combining Syntax)**

所有高级语法都可以自由组合，实现更精细的控制。

```text
[(masterpiece|best quality):1.2], a fantasy creature, {[lion|eagle]:1.3}, [fire:ice:0.5] powers
```

**解析**:

- `(masterpiece|best quality):1.2`: 融合“杰作”和“最高质量”两个词，并整体增强权重。
- `{[lion|eagle]:1.3}`: 创造狮鹫（狮子和鹰的混合体），并增强这个混合概念。
- `[fire:ice:0.5]`: 创造一种从火焰渐变为冰霜的能量特效。

---

## ⚠️ 五、负向提示词 (Negative Prompts)

告诉AI**不要画什么**，用于修正画面中不想要的内容。

**常用负向词**:

```text
(deformed, distorted, disfigured:1.3), low quality, worst quality, bad anatomy, ugly, extra limbs, missing limbs, mutated hands, extra fingers, signature, watermark, text, blurry
```

---

## 📋 六、实战模板 (Templates)

### **模板1: 写实风格融合人像**

```text
// 正向提示词
(photorealistic:1.2), masterpiece, close-up portrait of a woman, with [blonde|brunette] hair, wearing a {[leather|denim] jacket:1.2}, (cinematic lighting:1.1), soft smile, detailed skin texture

// 负向提示词
(deformed, ugly:1.3), cartoon, anime, 3d, painting, blurry
```

### **模板2: 奇幻混合生物**

```text
// 正向提示词
(epic fantasy art:1.2), masterpiece, a majestic [dragon|wolf] hybrid creature, glowing {[red|purple]:1.1} eyes, standing on a mountain peak, [day:night:0.4], dramatic storm clouds

// 负向提示词
photo, realistic, cute, low quality, poorly drawn
```

---

## 💡 七、最佳实践总结 (Best Practices)

1. **从简到繁**: 先写出核心主体，再逐步添加细节和高级语法。
2. **权重微调**: 权重值通常在 `0.7` 到 `1.5` 之间微调，过高或过低都可能导致画面崩坏。
3. **交替优于直接描述**: 想画“猫狗”，用 `[cat|dog]` 比 `cat and dog` 更容易获得融合特征的生物。
4. **善用负向提示词**: 这是提高出图质量和成功率最有效的方法之一。
5. **不断迭代**: 第一次的结果不理想很正常。根据结果，调整提示词、权重和融合方式，多次尝试。
