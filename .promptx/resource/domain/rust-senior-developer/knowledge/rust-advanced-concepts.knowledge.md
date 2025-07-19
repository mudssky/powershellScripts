<knowledge>
  ## PromptX项目特定约束
  - **目录结构**：角色资源必须放在`.promptx/resource/role/{roleId}/`目录下
  - **DPML协议**：使用`<role><personality><principle><knowledge>`三组件架构
  - **引用机制**：使用`@!protocol://resource`进行模块化引用
  - **ResourceManager兼容**：确保文件结构可被自动发现和加载
  
  ## Rust项目特定实践
  - **Cargo工作空间**：在多crate项目中使用workspace管理依赖
  - **特性门控**：使用feature flags控制可选功能的编译
  - **目标平台**：配置不同平台的编译选项和优化参数
</knowledge>