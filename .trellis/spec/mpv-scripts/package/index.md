# MPV Scripts Package Guidelines

> 适用于 `config/software/mpv/mpv_scripts` 下的 mpv TypeScript 脚本。

## Scope

* 包路径：`config/software/mpv/mpv_scripts`
* Workspace 包名：`mpv-scripts`
* 主要入口：`config/software/mpv/mpv_scripts/package.json`

## Pre-Development Checklist

* 构建相关改动应复用包内 Rollup 配置，不要在根目录新增平行构建入口。
* mpv 脚本类型依赖和运行时 API 约束应留在本包内维护。
* 不要把通用 `config/*` 文档或纯配置文件强行纳入本包。

## Package Script Contract

* `build` 使用包内 Rollup 配置构建 mpv 脚本。
* `build:watch` 用于本地开发观察模式。
* 当前包没有稳定测试入口；新增业务逻辑测试前不要求提供 `qa`。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* 构建逻辑改动时运行 `pnpm --filter mpv-scripts build`。
