<execution>
  <constraint>
    ## 技术环境限制
    - **Rust版本**：使用稳定版本，避免nightly特性在生产环境
    - **编译器要求**：充分利用借用检查器，不使用unsafe代码除非必要
    - **平台兼容性**：考虑目标平台的特定限制和优化机会
    - **依赖管理**：严格控制依赖版本，定期更新安全补丁
  </constraint>

  <rule>
    ## 强制性开发规则
    - **代码格式化**：使用rustfmt进行代码格式化，配置.rustfmt.toml
    - **静态分析**：使用clippy进行代码质量检查，修复所有警告
    - **测试覆盖**：单元测试覆盖率不低于80%，集成测试覆盖主要场景
    - **文档完整性**：所有公共API必须有文档注释和使用示例
    - **错误处理**：禁止使用unwrap()和expect()，除非在测试代码中
    - **并发安全**：多线程代码必须通过Miri内存模型检查
  </rule>

  <guideline>
    ## 开发指导原则
    - **渐进式开发**：从最简实现开始，逐步添加功能和优化
    - **类型驱动设计**：充分利用Rust类型系统表达业务逻辑
    - **组合优于继承**：使用trait和泛型实现代码复用
    - **显式优于隐式**：明确表达意图，避免隐式转换和魔法数字
    - **性能意识**：了解每个抽象的性能成本，在需要时进行优化
    - **社区标准**：遵循Rust社区的命名约定和API设计模式
  </guideline>

  <process>
    ## 标准开发流程
    
    ### Step 1: 项目初始化
    ```bash
    cargo new project_name
    cd project_name
    # 配置Cargo.toml
    # 设置.gitignore
    # 配置CI/CD
    ```
    
    ### Step 2: 架构设计
    ```mermaid
    graph TD
        A[需求分析] --> B[模块设计]
        B --> C[数据结构定义]
        C --> D[trait接口设计]
        D --> E[错误类型定义]
        E --> F[测试用例设计]
    ```
    
    ### Step 3: 核心开发循环
    ```mermaid
    flowchart LR
        A[编写代码] --> B[cargo check]
        B --> C[cargo test]
        C --> D[cargo clippy]
        D --> E[cargo fmt]
        E --> F{通过检查?}
        F -->|是| G[提交代码]
        F -->|否| A
    ```
    
    ### Step 4: 质量保证
    ```bash
    # 运行完整测试套件
    cargo test --all-features
    
    # 性能基准测试
    cargo bench
    
    # 内存安全检查
    cargo +nightly miri test
    
    # 文档生成和检查
    cargo doc --no-deps --open
    ```
    
    ### Step 5: 发布准备
    ```mermaid
    graph TD
        A[版本号更新] --> B[CHANGELOG更新]
        B --> C[文档完善]
        C --> D[示例代码验证]
        D --> E[cargo publish --dry-run]
        E --> F[cargo publish]
    ```
    
    ## 代码审查检查清单
    
    ### 安全性检查
    - [ ] 没有不必要的unsafe代码
    - [ ] 所有输入都经过验证
    - [ ] 敏感数据得到适当保护
    - [ ] 并发代码没有数据竞争
    
    ### 性能检查
    - [ ] 避免不必要的内存分配
    - [ ] 合理使用引用而非克隆
    - [ ] 热点路径经过优化
    - [ ] 算法复杂度符合预期
    
    ### 可维护性检查
    - [ ] 代码结构清晰，职责分离
    - [ ] 函数长度适中，逻辑简单
    - [ ] 变量和函数命名清晰
    - [ ] 注释解释了"为什么"而非"是什么"
  </process>

  <criteria>
    ## 质量评价标准

    ### 代码质量指标
    - ✅ 编译无警告
    - ✅ Clippy检查通过
    - ✅ 测试覆盖率 ≥ 80%
    - ✅ 文档覆盖率 ≥ 90%
    - ✅ 基准测试性能达标

    ### 安全性指标
    - ✅ Miri检查通过
    - ✅ 无unsafe代码或经过充分审查
    - ✅ 依赖项安全扫描通过
    - ✅ 模糊测试无崩溃

    ### 可维护性指标
    - ✅ 代码复杂度适中
    - ✅ 模块耦合度低
    - ✅ API设计一致性
    - ✅ 错误处理完整性

    ### 性能指标
    - ✅ 内存使用效率
    - ✅ CPU使用效率
    - ✅ 编译时间合理
    - ✅ 二进制大小适中
  </criteria>
</execution>