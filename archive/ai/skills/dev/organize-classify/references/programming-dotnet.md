# .NET 项目目录结构

## 先识别

- 是否有 `.sln`、`.csproj`、`.fsproj`、`.vbproj`、`Directory.Build.props`。
- 是库、控制台应用、ASP.NET、桌面应用、测试项目还是多项目 solution。
- ASP.NET、MAUI、Blazor 等框架项目先查官方目录约定。

## 常见 solution 结构

```text
project/
  Project.sln
  src/
    App/
      App.csproj
    Library/
      Library.csproj
  tests/
    App.Tests/
      App.Tests.csproj
```

小项目也可以保持：

```text
project/
  App.csproj
  Program.cs
  App.Tests/
```

## 放置建议

- 按 project 边界组织源码，而不是只按文件类型。
- 测试项目通常独立，命名为 `<Project>.Tests` 或团队约定形式。
- solution 负责聚合项目；不要手工移动 `.csproj` 后忘记更新 `.sln`。
- 共享构建配置可放 `Directory.Build.props` / `Directory.Build.targets`。
- appsettings 示例和本机 secret 分开，真实 secret 不提交。

## 避免

- 把所有项目塞进一个目录导致 `.sln`、project reference 和命名空间混乱。
- 移动项目后忘记更新 project reference、namespace、content files、launch settings 和 CI 路径。
- 用通用结构覆盖 ASP.NET 等框架的约定目录。
