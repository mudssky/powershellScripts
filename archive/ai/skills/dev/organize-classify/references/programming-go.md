# Go 项目目录结构

## 先识别

- 是否有 `go.mod` 和 module path。
- 是单命令工具、多命令工具、库、服务还是 monorepo。
- 是否已有 `cmd/`、`internal/`、`pkg/` 或框架约定。

## 常见结构

单命令项目可以很简单：

```text
project/
  go.mod
  main.go
  main_test.go
```

多命令或服务项目常见：

```text
project/
  go.mod
  cmd/
    tool/
      main.go
  internal/
    app/
    config/
  pkg/
    publiclib/
```

## 放置建议

- `cmd/<name>/main.go` 放命令入口，保持薄。
- `internal/` 放只给当前 module 使用的私有包。
- `pkg/` 只放确实要给外部项目 import 的公共库；不要把所有代码都塞进 `pkg`。
- 测试通常与包同目录，文件名为 `*_test.go`。
- 配置示例和部署文件按项目用途放 `configs/`、`deploy/` 或框架/平台约定位置。

## 避免

- 过早套大型标准布局，让小工具变复杂。
- 误把可私有的包放到 `pkg/` 暴露公共 API。
- 移动包后忘记更新 import path、go:embed 路径和 CI 命令。
