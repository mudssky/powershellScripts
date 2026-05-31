# JVM 项目目录结构

## 先识别

- 使用 Maven、Gradle、Bazel 还是其他构建系统。
- 语言是 Java、Kotlin、Scala，或混合项目。
- 是单模块、多模块、库、服务还是框架项目。
- Spring Boot、Android、Micronaut、Quarkus 等框架先查官方目录约定。

## Maven/Gradle 常见结构

```text
project/
  pom.xml | build.gradle(.kts)
  src/
    main/
      java/ | kotlin/
      resources/
    test/
      java/ | kotlin/
      resources/
```

多模块常见：

```text
project/
  settings.gradle(.kts) | parent pom.xml
  module-a/
    src/main/...
    src/test/...
  module-b/
    src/main/...
    src/test/...
```

## 放置建议

- 源码跟随构建系统约定，不随意发明平行源码目录。
- resources 放运行时资源，test resources 放测试资源。
- package 命名和目录层级保持一致。
- 多模块按可独立构建、发布、部署或清晰职责拆分。
- 共享测试 fixture 可放测试工具模块或构建系统约定目录。

## 避免

- 把 Spring/Android 等框架目录改成通用 JVM 结构。
- 让模块边界只按技术层拆分而没有发布或职责价值。
- 移动包后忘记更新 package 声明、扫描配置、资源路径和构建脚本。
