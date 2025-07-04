<execution id="golang-workflow">
  <constraint>
    ## Go开发约束条件
    - **Go版本**：使用稳定版本，关注新特性兼容性
    - **模块管理**：必须使用Go modules进行依赖管理
    - **代码规范**：严格遵循gofmt、golint、go vet规范
    - **测试覆盖**：单元测试覆盖率不低于80%
    - **性能要求**：关键路径必须进行性能测试
    - **安全规范**：遵循Go安全编码规范
  </constraint>

  <rule>
    ## 强制性开发规则
    - **错误处理**：所有可能出错的地方必须显式处理错误
    - **资源管理**：使用defer确保资源正确释放
    - **并发安全**：共享数据必须使用适当的同步机制
    - **接口设计**：优先定义小接口，遵循接口隔离原则
    - **包命名**：使用简洁、描述性的包名，避免冲突
    - **文档注释**：公开的函数、类型必须有文档注释
  </rule>

  <guideline>
    ## 开发指导原则
    - **简洁优雅**：代码简洁清晰，避免过度设计
    - **性能优先**：在保证正确性的前提下追求性能
    - **可测试性**：设计易于测试的代码结构
    - **可维护性**：考虑代码的长期维护成本
    - **渐进式优化**：先实现功能，再进行性能优化
  </guideline>

  <process>
    ## Go项目开发流程
    
    ### 项目初始化
    ```bash
    # 1. 创建项目目录
    mkdir myproject && cd myproject
    
    # 2. 初始化Go模块
    go mod init github.com/username/myproject
    
    # 3. 创建基本目录结构
    mkdir -p {cmd,internal,pkg,api,web,configs,scripts,test,docs}
    
    # 4. 创建主程序入口
    touch cmd/main.go
    
    # 5. 初始化git仓库
    git init && git add . && git commit -m "Initial commit"
    ```
    
    ### 标准目录结构
    ```
    myproject/
    ├── cmd/                 # 主程序入口
    │   └── main.go
    ├── internal/            # 私有代码
    │   ├── handler/         # HTTP处理器
    │   ├── service/         # 业务逻辑
    │   ├── repository/      # 数据访问
    │   └── config/          # 配置管理
    ├── pkg/                 # 可复用的库代码
    ├── api/                 # API定义文件
    ├── web/                 # 静态文件
    ├── configs/             # 配置文件
    ├── scripts/             # 构建脚本
    ├── test/                # 测试文件
    ├── docs/                # 文档
    ├── go.mod               # 模块定义
    ├── go.sum               # 依赖校验
    ├── Makefile             # 构建脚本
    ├── Dockerfile           # 容器化
    └── README.md            # 项目说明
    ```
    
    ### 开发工作流
    ```mermaid
    flowchart TD
        A[需求分析] --> B[接口设计]
        B --> C[数据结构设计]
        C --> D[编写测试用例]
        D --> E[实现功能代码]
        E --> F[运行测试]
        F --> G{测试通过?}
        G -->|否| E
        G -->|是| H[代码审查]
        H --> I[性能测试]
        I --> J[文档更新]
        J --> K[提交代码]
    ```
    
    ### 代码编写流程
    1. **接口定义**：先定义接口，明确契约
    2. **测试驱动**：编写测试用例，明确预期行为
    3. **实现功能**：实现接口，满足测试要求
    4. **错误处理**：完善错误处理逻辑
    5. **性能优化**：根据需要进行性能优化
    6. **文档完善**：更新代码注释和文档
    
    ### 测试策略
    ```mermaid
    graph TD
        A[单元测试] --> B[集成测试]
        B --> C[性能测试]
        C --> D[端到端测试]
        
        A1[函数级测试] --> A
        A2[模块级测试] --> A
        
        B1[组件集成] --> B
        B2[数据库集成] --> B
        
        C1[基准测试] --> C
        C2[压力测试] --> C
        
        D1[API测试] --> D
        D2[用户场景测试] --> D
    ```
    
    ### 质量保证流程
    ```bash
    # 1. 代码格式化
    go fmt ./...
    
    # 2. 代码检查
    go vet ./...
    golint ./...
    
    # 3. 安全检查
    gosec ./...
    
    # 4. 运行测试
    go test -v -race -coverprofile=coverage.out ./...
    
    # 5. 查看覆盖率
    go tool cover -html=coverage.out
    
    # 6. 性能测试
    go test -bench=. -benchmem ./...
    
    # 7. 依赖检查
    go mod tidy
    go mod verify
    ```
  </process>

  <criteria>
    ## 代码质量标准

    ### 功能正确性
    - ✅ 所有测试用例通过
    - ✅ 边界条件正确处理
    - ✅ 错误情况妥善处理
    - ✅ 并发安全性验证

    ### 性能指标
    - ✅ 关键路径性能满足要求
    - ✅ 内存使用合理
    - ✅ 无明显性能瓶颈
    - ✅ 并发性能良好

    ### 代码质量
    - ✅ 代码风格一致
    - ✅ 命名清晰准确
    - ✅ 逻辑结构清晰
    - ✅ 注释完整准确

    ### 可维护性
    - ✅ 模块职责单一
    - ✅ 依赖关系清晰
    - ✅ 易于扩展修改
    - ✅ 文档完整更新
  </criteria>
</execution>