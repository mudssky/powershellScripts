<constraint>
  ## 测试约束条件
  - **测试覆盖率**：核心功能必须达到90%以上覆盖率
  - **测试独立性**：每个测试用例必须独立运行
  - **测试速度**：单元测试执行时间不超过合理范围
  - **测试环境**：测试不能依赖外部服务或网络
  - **数据隔离**：测试数据不能影响生产环境
</constraint>

<rule>
  ## 测试强制规则
  - **TDD原则**：核心功能必须先写测试再写实现
  - **测试命名**：测试函数名必须清晰描述测试场景
  - **断言明确**：每个测试必须有明确的断言
  - **异常测试**：必须测试异常情况和边界条件
  - **Mock使用**：外部依赖必须使用Mock进行隔离
</rule>

<guideline>
  ## 测试指导原则
  - **测试金字塔**：大量单元测试，适量集成测试，少量端到端测试
  - **可读性优先**：测试代码应该比生产代码更易读
  - **快速反馈**：测试应该能够快速发现问题
  - **持续维护**：测试代码需要与生产代码同步维护
  - **文档作用**：测试用例应该能够作为代码的使用文档
</guideline>

<process>
  ## Python测试策略实施
  
  ### 测试环境搭建
  ```bash
  # 1. 安装测试框架和工具
  pip install pytest pytest-cov pytest-mock pytest-xdist
  pip install factory-boy faker hypothesis
  
  # 2. 创建测试配置文件
  # pytest.ini 或 pyproject.toml
  [tool.pytest.ini_options]
  testpaths = ["tests"]
  python_files = ["test_*.py", "*_test.py"]
  python_classes = ["Test*"]
  python_functions = ["test_*"]
  addopts = "--cov=src --cov-report=html --cov-report=term"
  
  # 3. 设置测试目录结构
  tests/
  ├── unit/           # 单元测试
  ├── integration/    # 集成测试
  ├── e2e/           # 端到端测试
  ├── fixtures/      # 测试数据
  └── conftest.py    # 测试配置
  ```
  
  ### 单元测试编写
  ```python
  # 1. 基础单元测试
  import pytest
  from unittest.mock import Mock, patch
  
  def test_function_with_valid_input():
      # Given
      input_data = "valid_input"
      expected_result = "expected_output"
      
      # When
      result = my_function(input_data)
      
      # Then
      assert result == expected_result
  
  # 2. 异常测试
  def test_function_with_invalid_input():
      with pytest.raises(ValueError, match="Invalid input"):
          my_function("invalid_input")
  
  # 3. 参数化测试
  @pytest.mark.parametrize("input_val,expected", [
      ("input1", "output1"),
      ("input2", "output2"),
      ("input3", "output3"),
  ])
  def test_function_with_multiple_inputs(input_val, expected):
      assert my_function(input_val) == expected
  
  # 4. Mock测试
  @patch('module.external_service')
  def test_function_with_external_dependency(mock_service):
      mock_service.return_value = "mocked_response"
      result = function_using_external_service()
      assert result == "expected_result"
      mock_service.assert_called_once()
  ```
  
  ### 集成测试策略
  ```python
  # 1. 数据库集成测试
  @pytest.fixture
  def test_db():
      # 创建测试数据库
      db = create_test_database()
      yield db
      # 清理测试数据库
      db.drop_all()
  
  def test_user_creation_integration(test_db):
      user_service = UserService(test_db)
      user = user_service.create_user("test@example.com")
      assert user.email == "test@example.com"
      assert user.id is not None
  
  # 2. API集成测试
  def test_api_endpoint_integration(test_client):
      response = test_client.post("/api/users", json={
          "email": "test@example.com",
          "name": "Test User"
      })
      assert response.status_code == 201
      assert response.json()["email"] == "test@example.com"
  ```
  
  ### 测试数据管理
  ```python
  # 1. 使用Factory Boy创建测试数据
  import factory
  from factory import Faker
  
  class UserFactory(factory.Factory):
      class Meta:
          model = User
      
      email = Faker('email')
      name = Faker('name')
      age = Faker('random_int', min=18, max=80)
  
  # 2. 使用Fixture提供测试数据
  @pytest.fixture
  def sample_user():
      return UserFactory()
  
  @pytest.fixture
  def user_list():
      return UserFactory.create_batch(5)
  
  # 3. 使用Hypothesis进行属性测试
  from hypothesis import given, strategies as st
  
  @given(st.text(min_size=1, max_size=100))
  def test_string_processing(input_string):
      result = process_string(input_string)
      assert isinstance(result, str)
      assert len(result) >= 0
  ```
  
  ### 测试执行和报告
  ```bash
  # 1. 运行所有测试
  pytest
  
  # 2. 运行特定测试
  pytest tests/unit/test_user.py::test_user_creation
  
  # 3. 并行执行测试
  pytest -n auto
  
  # 4. 生成覆盖率报告
  pytest --cov=src --cov-report=html
  
  # 5. 运行性能测试
  pytest --benchmark-only
  
  # 6. 生成测试报告
  pytest --html=report.html --self-contained-html
  ```
</process>

<criteria>
  ## 测试质量标准
  
  ### 覆盖率要求
  - **语句覆盖率** ≥ 90%
  - **分支覆盖率** ≥ 85%
  - **函数覆盖率** = 100%
  - **关键路径覆盖率** = 100%
  
  ### 测试性能指标
  - **单元测试执行时间** ≤ 10秒
  - **集成测试执行时间** ≤ 2分钟
  - **测试成功率** ≥ 99%
  - **测试稳定性** 无随机失败
  
  ### 测试代码质量
  - **测试可读性** 清晰易懂
  - **测试维护性** 易于修改
  - **测试独立性** 无相互依赖
  - **测试完整性** 覆盖所有场景
  
  ### 测试文档要求
  - **测试计划** 明确测试策略
  - **测试用例** 详细测试场景
  - **测试报告** 定期生成报告
  - **缺陷跟踪** 记录和修复缺陷
</criteria>