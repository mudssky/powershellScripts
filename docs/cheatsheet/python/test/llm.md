这是一份针对 Python + Pytest 开发 LLM 应用的测试最佳实践速查表（Cheatsheet）。核心理念是 **“测试分层”**：将逻辑、协议和模型效果分开测试。

---

### 🛠️ 核心工具栈 (Tech Stack)

```bash
# 必装
uv add --dev pytest pytest-mock pytest-recording  # 录制回放神器
uv add --dev pytest-asyncio  # 如果你的 LLM 调用是异步的
uv add pydantic  # 用于结构化校验
```

---

### 🏗️ Level 1: 纯逻辑单元测试 (Unit Tests)

**目标**：测试 Prompt 拼装、JSON 解析、结果后处理。**绝对不联网**。

| 场景 | 技巧 | 关键代码 |
| :--- | :--- | :--- |
| **测试 Prompt 模板** | 直接断言字符串 | `assert prompt == "User: Hello"` |
| **测试结果解析** | Mock Client 返回值 | `mock_resp.choices[0].message.content = "..."` |
| **测试异常处理** | Mock 抛出异常 | `side_effect=openai.APIError` |

**Code Snippet:**

```python
from unittest.mock import MagicMock, patch

def test_prompt_parsing():
    # 模拟 LLM 返回了脏数据，测试你的清洗函数是否健壮
    mock_ret = MagicMock()
    mock_ret.choices[0].message.content = ' ```json\n{"val": 1}\n``` '
    
    with patch("openai.resources.chat.Completions.create", return_value=mock_ret):
        result = my_llm_function("input")
        assert result == {"val": 1}  # 验证解析逻辑
```

---

### 📼 Level 2: 协议级集成测试 (VCR / Replay)

**目标**：测试 API 连通性、Pydantic 定义与 API 返回是否对齐。**录制一次，永久回放**。
**特点**：速度快（毫秒级）、零成本、结果确定。

**配置 (conftest.py):**

```python
import pytest

@pytest.fixture(scope="module")
def vcr_config():
    # 重要：防止将真实的 API Key 录制到文件中
    return {"filter_headers": [("authorization", "Bearer <HIDDEN>")]}
```

**Code Snippet:**

```python
import pytest

# 第一次跑会真调并生成 yaml 文件，之后跑直接读文件
@pytest.mark.vcr
def test_integration_with_openai_protocol():
    response = call_real_llm("Say 'Hello'")
    assert response == "Hello"
```

---

### 🧠 Level 3: 效果评估测试 (Evals / Real Call)

**目标**：测试 Prompt 改动后的智能程度。**真实调用，耗时耗钱**。
**断言策略**：由于结果不确定，不能用 `==`。

| 断言类型 | 方法 | 适用场景 |
| :--- | :--- | :--- |
| **结构断言** | `assert "key" in result` | 输出必须包含某些字段 |
| **模糊断言** | `assert len(res) > 50` | 长度、关键词检查 |
| **确定性校验** | `verify_json_schema(res)` | 强制输出 JSON 格式时 |
| **语义裁判** | `assert llm_judge(res) > 8` | 让 GPT-4 给当前结果打分 |

**Code Snippet:**

```python
@pytest.mark.ai_model  # 打标，平时跳过
def test_summarization_quality():
    summary = generate_summary(LONG_TEXT)
    
    # 1. 刚性断言 (Pydantic)
    assert isinstance(summary, SummaryModel)
    
    # 2. 柔性断言 (关键词)
    assert any(w in summary.text for w in ["关键点A", "关键点B"])
    
    # 3. 语义断言 (伪代码: 用 embedding 算相似度)
    # assert cosine_similarity(summary.text, reference) > 0.8
```

---

### 🚀 运行与工作流 (Workflow)

建议在 `pyproject.toml` 或 `pytest.ini` 中定义 Marker：

```ini
[tool.pytest.ini_options]
markers = [
    "vcr: marks tests as VCR cassettes (fast integration)",
    "ai_model: marks tests that make REAL expensive calls (slow)",
]
```

**日常开发 (Dev Loop):**

```bash
# 跑逻辑测试 + 回放测试 (全覆盖，极快)
uv run pytest -m "not ai_model"
```

**提交代码/CI (PR Check):**

```bash
# 同上，确保不破坏现有功能
uv run pytest -m "not ai_model"
```

**Prompt 调优/上线前 (Release):**

```bash
# 只跑真实 LLM 请求，验证效果
uv run pytest -m "ai_model"
```

---

### 💡 黄金法则 (Golden Rules)

1. **分离 IO 与 逻辑**：不要把 `openai.chat.completions.create` 埋在深层业务逻辑里。把它封装成单独的 `Client` 类，方便 Mock。
2. **不要手动 Mock 网络库**：不要去 Mock `requests` 或 `httpx`，太复杂且容易错。直接用 `pytest-recording` (VCR)。
3. **确定性优先**：对于 Temperature=0 的任务，VCR 是完美的。对于高创造性任务，使用 LLM-as-a-Judge。
4. **保护钱包**：务必在 `conftest.py` 里配置 VCR 过滤 Header，否则你把录像文件传到 GitHub 上就泄露 Key 了。
