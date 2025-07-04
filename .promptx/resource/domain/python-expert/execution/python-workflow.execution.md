<constraint>
  ## Python开发约束
  - **Python版本**：明确支持的Python版本范围
  - **依赖管理**：使用标准的依赖管理工具和格式
  - **代码规范**：严格遵循PEP 8和团队编码标准
  - **测试要求**：确保充分的测试覆盖率
  - **文档标准**：提供清晰完整的文档
</constraint>

<rule>
  ## 开发强制规则
  - **虚拟环境**：必须使用虚拟环境隔离项目依赖
  - **版本控制**：所有代码必须纳入Git版本控制
  - **代码审查**：所有代码变更必须经过审查
  - **测试先行**：核心功能必须有对应的单元测试
  - **安全检查**：定期进行安全漏洞扫描
</rule>

<guideline>
  ## 开发指导原则
  - **渐进式开发**：从简单版本开始，逐步完善功能
  - **模块化设计**：保持代码模块的独立性和可复用性
  - **性能意识**：在设计阶段考虑性能影响
  - **用户体验**：关注API的易用性和一致性
  - **可维护性**：编写易于理解和修改的代码
</guideline>

<process>
  ## Python项目开发流程
  
  ### 项目初始化阶段
  ```bash
  # 1. 创建项目目录
  mkdir my-python-project
  cd my-python-project
  
  # 2. 创建虚拟环境
  python -m venv venv
  source venv/bin/activate  # Windows: venv\Scripts\activate
  
  # 3. 初始化Git仓库
  git init
  
  # 4. 创建基础文件
  touch README.md .gitignore requirements.txt
  
  # 5. 设置项目结构
  mkdir src tests docs
  ```
  
  ### 开发环境配置
  ```bash
  # 1. 安装开发依赖
  pip install pytest black isort flake8 mypy
  
  # 2. 配置代码格式化工具
  # 创建 pyproject.toml 配置文件
  
  # 3. 配置IDE/编辑器
  # 设置Python解释器路径
  # 配置代码格式化和静态检查
  ```
  
  ### 功能开发循环
  ```python
  # 1. 编写测试用例
  def test_new_feature():
      # 测试新功能的预期行为
      pass
  
  # 2. 实现功能代码
  def new_feature():
      # 实现具体功能
      pass
  
  # 3. 运行测试验证
  pytest tests/
  
  # 4. 代码格式化和检查
  black src/
  isort src/
  flake8 src/
  mypy src/
  ```
  
  ### 代码提交流程
  ```bash
  # 1. 检查代码质量
  black --check src/
  isort --check-only src/
  flake8 src/
  mypy src/
  
  # 2. 运行完整测试
  pytest tests/ --cov=src/
  
  # 3. 提交代码
  git add .
  git commit -m "feat: add new feature"
  
  # 4. 推送到远程仓库
  git push origin feature-branch
  ```
  
  ### 发布准备流程
  ```bash
  # 1. 更新版本号
  # 修改 __init__.py 或 pyproject.toml 中的版本
  
  # 2. 更新文档
  # 更新 README.md 和 CHANGELOG.md
  
  # 3. 构建包
  python -m build
  
  # 4. 测试安装
  pip install dist/package-name.whl
  
  # 5. 发布到PyPI
  twine upload dist/*
  ```
</process>

<criteria>
  ## 质量评估标准
  
  ### 代码质量指标
  - **测试覆盖率** ≥ 80%
  - **代码复杂度** ≤ 10 (McCabe)
  - **PEP 8合规率** = 100%
  - **类型注解覆盖率** ≥ 90%
  
  ### 性能基准
  - **启动时间** ≤ 预期值
  - **内存使用** ≤ 合理范围
  - **响应时间** ≤ 用户期望
  - **并发处理** ≥ 最低要求
  
  ### 文档完整性
  - **API文档** 100%覆盖
  - **使用示例** 充分详细
  - **安装说明** 清晰准确
  - **贡献指南** 完整可操作
  
  ### 安全标准
  - **依赖漏洞** = 0个高危
  - **代码扫描** 通过安全检查
  - **敏感信息** 无泄露风险
  - **输入验证** 充分防护
</criteria>