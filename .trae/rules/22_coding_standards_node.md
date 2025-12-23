---
alwaysApply: false
globs: *.js,*.ts
---
# 🛡️ Coding Standards (Node.js/TypeScript)

## 1. Naming Conventions

- **Files**: `kebab-case.ts` (推荐) 或 `camelCase.ts`。
- **Variables**: `camelCase`.
- **Functions**: `camelCase`.
- **Classes**: `PascalCase`.

## 2. Documentation

- **JSDoc**: 导出函数必须包含 JSDoc (`@param`, `@returns`)。

## 3. Error Handling

- **Async/Await**: 必须处理 Promise rejection (使用 `try/catch` 或 `.catch()`)。
- **Types**: 严禁使用 `any`，必须定义明确的 Interface/Type。
