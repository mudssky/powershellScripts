<execution id="testing-strategy">
  <constraint>
    ## 测试约束条件
    - **覆盖率要求**：单元测试覆盖率不低于80%，核心模块不低于90%
    - **测试隔离**：每个测试用例必须独立，不依赖其他测试
    - **测试数据**：使用模拟数据，避免依赖外部服务
    - **测试环境**：支持并行测试，使用-race检测竞态条件
    - **性能基准**：关键函数必须有benchmark测试
  </constraint>

  <rule>
    ## 测试强制规则
    - **命名规范**：测试函数以Test开头，基准测试以Benchmark开头
    - **文件组织**：测试文件以_test.go结尾，与被测试文件同包
    - **错误处理**：测试中的错误必须使用t.Error或t.Fatal报告
    - **清理资源**：使用t.Cleanup或defer确保测试资源清理
    - **并发安全**：并发测试必须使用t.Parallel()标记
  </rule>

  <guideline>
    ## 测试指导原则
    - **测试驱动**：先写测试，再写实现代码
    - **简单明确**：每个测试只验证一个功能点
    - **可读性强**：测试代码要清晰表达测试意图
    - **快速执行**：单元测试应该快速执行完成
    - **稳定可靠**：测试结果应该稳定，不受环境影响
  </guideline>

  <process>
    ## Go测试完整策略
    
    ### 测试金字塔
    ```mermaid
    graph TD
        A[端到端测试 5%] --> B[集成测试 15%]
        B --> C[单元测试 80%]
        
        style A fill:#ff9999
        style B fill:#ffcc99
        style C fill:#99ff99
    ```
    
    ### 单元测试策略
    ```go
    // 基本单元测试模板
    func TestFunctionName(t *testing.T) {
        // Arrange - 准备测试数据
        input := "test input"
        expected := "expected output"
        
        // Act - 执行被测试函数
        result := FunctionName(input)
        
        // Assert - 验证结果
        if result != expected {
            t.Errorf("FunctionName(%v) = %v, want %v", input, result, expected)
        }
    }
    
    // 表格驱动测试
    func TestFunctionNameTable(t *testing.T) {
        tests := []struct {
            name     string
            input    string
            expected string
            wantErr  bool
        }{
            {"valid input", "test", "expected", false},
            {"empty input", "", "", true},
            {"special chars", "test@#$", "processed", false},
        }
        
        for _, tt := range tests {
            t.Run(tt.name, func(t *testing.T) {
                result, err := FunctionName(tt.input)
                
                if (err != nil) != tt.wantErr {
                    t.Errorf("FunctionName() error = %v, wantErr %v", err, tt.wantErr)
                    return
                }
                
                if result != tt.expected {
                    t.Errorf("FunctionName() = %v, want %v", result, tt.expected)
                }
            })
        }
    }
    ```
    
    ### Mock和Stub策略
    ```go
    // 接口定义
    type UserRepository interface {
        GetUser(id int) (*User, error)
        SaveUser(user *User) error
    }
    
    // Mock实现
    type MockUserRepository struct {
        users map[int]*User
        err   error
    }
    
    func (m *MockUserRepository) GetUser(id int) (*User, error) {
        if m.err != nil {
            return nil, m.err
        }
        return m.users[id], nil
    }
    
    func (m *MockUserRepository) SaveUser(user *User) error {
        if m.err != nil {
            return m.err
        }
        m.users[user.ID] = user
        return nil
    }
    
    // 使用Mock进行测试
    func TestUserService_GetUser(t *testing.T) {
        mockRepo := &MockUserRepository{
            users: map[int]*User{
                1: {ID: 1, Name: "John"},
            },
        }
        
        service := NewUserService(mockRepo)
        user, err := service.GetUser(1)
        
        assert.NoError(t, err)
        assert.Equal(t, "John", user.Name)
    }
    ```
    
    ### 集成测试策略
    ```go
    // 数据库集成测试
    func TestUserRepository_Integration(t *testing.T) {
        if testing.Short() {
            t.Skip("Skipping integration test in short mode")
        }
        
        // 设置测试数据库
        db := setupTestDB(t)
        defer cleanupTestDB(t, db)
        
        repo := NewUserRepository(db)
        
        // 测试保存用户
        user := &User{Name: "Test User", Email: "test@example.com"}
        err := repo.SaveUser(user)
        assert.NoError(t, err)
        assert.NotZero(t, user.ID)
        
        // 测试获取用户
        retrieved, err := repo.GetUser(user.ID)
        assert.NoError(t, err)
        assert.Equal(t, user.Name, retrieved.Name)
    }
    ```
    
    ### 性能测试策略
    ```go
    // 基准测试
    func BenchmarkFunctionName(b *testing.B) {
        input := "test input"
        
        b.ResetTimer()
        for i := 0; i < b.N; i++ {
            FunctionName(input)
        }
    }
    
    // 内存分配测试
    func BenchmarkFunctionNameMemory(b *testing.B) {
        input := "test input"
        
        b.ReportAllocs()
        b.ResetTimer()
        
        for i := 0; i < b.N; i++ {
            result := FunctionName(input)
            _ = result // 避免编译器优化
        }
    }
    
    // 并发性能测试
    func BenchmarkFunctionNameParallel(b *testing.B) {
        input := "test input"
        
        b.RunParallel(func(pb *testing.PB) {
            for pb.Next() {
                FunctionName(input)
            }
        })
    }
    ```
    
    ### 测试工具和辅助函数
    ```go
    // 测试辅助函数
    func setupTestDB(t *testing.T) *sql.DB {
        db, err := sql.Open("sqlite3", ":memory:")
        if err != nil {
            t.Fatalf("Failed to open test database: %v", err)
        }
        
        // 执行schema创建
        if err := createSchema(db); err != nil {
            t.Fatalf("Failed to create schema: %v", err)
        }
        
        return db
    }
    
    func cleanupTestDB(t *testing.T, db *sql.DB) {
        if err := db.Close(); err != nil {
            t.Errorf("Failed to close test database: %v", err)
        }
    }
    
    // 测试数据生成器
    func generateTestUser() *User {
        return &User{
            Name:  fmt.Sprintf("User_%d", rand.Int()),
            Email: fmt.Sprintf("user%d@test.com", rand.Int()),
        }
    }
    ```
    
    ### 测试执行命令
    ```bash
    # 运行所有测试
    go test ./...
    
    # 运行测试并显示覆盖率
    go test -cover ./...
    
    # 生成详细覆盖率报告
    go test -coverprofile=coverage.out ./...
    go tool cover -html=coverage.out
    
    # 运行竞态检测
    go test -race ./...
    
    # 运行基准测试
    go test -bench=. ./...
    
    # 运行基准测试并显示内存分配
    go test -bench=. -benchmem ./...
    
    # 只运行单元测试（跳过集成测试）
    go test -short ./...
    
    # 运行特定测试
    go test -run TestFunctionName ./...
    
    # 并行运行测试
    go test -parallel 4 ./...
    ```
  </process>

  <criteria>
    ## 测试质量标准

    ### 覆盖率指标
    - ✅ 单元测试覆盖率 ≥ 80%
    - ✅ 核心业务逻辑覆盖率 ≥ 90%
    - ✅ 分支覆盖率 ≥ 70%
    - ✅ 函数覆盖率 ≥ 85%

    ### 测试质量
    - ✅ 测试用例独立性
    - ✅ 测试数据完整性
    - ✅ 边界条件覆盖
    - ✅ 异常情况处理

    ### 性能指标
    - ✅ 单元测试执行时间 < 100ms
    - ✅ 集成测试执行时间 < 5s
    - ✅ 基准测试稳定性
    - ✅ 内存分配合理性

    ### 维护性
    - ✅ 测试代码可读性
    - ✅ 测试用例可维护性
    - ✅ Mock对象合理性
    - ✅ 测试文档完整性
  </criteria>
</execution>