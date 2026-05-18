#!/usr/bin/env bash
set -euo pipefail

# 这个脚本只把宿主配置作为只读来源接入容器。
# 运行态目录留在容器内，避免 Codex / Claude Code 把会话和日志写回宿主配置目录。
USER_HOME="${HOME:-/home/vscode}"

mkdir -p \
  "$USER_HOME/.m2" \
  "$USER_HOME/.codex" \
  "$USER_HOME/.claude" \
  "$USER_HOME/.codex/log" \
  "$USER_HOME/.codex/sessions" \
  "$USER_HOME/.codex/tmp" \
  "$USER_HOME/.claude/history" \
  "$USER_HOME/.claude/projects" \
  "$USER_HOME/.claude/sessions" \
  "$USER_HOME/.claude/todos"

if [ -s "/mnt/host-configs/claude.json" ]; then
  if [ -L "$USER_HOME/.claude.json" ] || [ ! -e "$USER_HOME/.claude.json" ]; then
    rm -f "$USER_HOME/.claude.json"
    ln -s "/mnt/host-configs/claude.json" "$USER_HOME/.claude.json"
  else
    echo "skip existing Claude Code root config: $USER_HOME/.claude.json"
  fi
fi

# Maven 配置文件只读链接到宿主配置；本地仓库由 devcontainer.json 单独读写挂载。
for maven_file in settings.xml settings-security.xml toolchains.xml; do
  source_path="/mnt/host-configs/m2/$maven_file"
  target_path="$USER_HOME/.m2/$maven_file"

  if [ -e "$source_path" ]; then
    if [ -L "$target_path" ] || [ ! -e "$target_path" ]; then
      rm -f "$target_path"
      ln -s "$source_path" "$target_path"
    else
      echo "skip existing Maven config: $target_path"
    fi
  fi
done

# Codex 配置采用白名单链接，避免把宿主日志、会话和 sqlite 状态库放进容器运行态。
for codex_path in \
  AGENTS.md \
  RTK.md \
  auth.json \
  config.toml \
  model_catalog.json \
  prompts \
  agents \
  rules \
  skills \
  plugins; do
  source_path="/mnt/host-configs/codex/$codex_path"
  target_path="$USER_HOME/.codex/$codex_path"
  target_dir="$(dirname "$target_path")"

  if [ -e "$source_path" ]; then
    mkdir -p "$target_dir"
    if [ -L "$target_path" ] || [ ! -e "$target_path" ]; then
      rm -f "$target_path"
      ln -s "$source_path" "$target_path"
    else
      echo "skip existing Codex config: $target_path"
    fi
  fi
done

# Claude Code 只链接共享配置与登录相关文件，history / sessions / todos 保持容器内可写。
for claude_path in \
  CLAUDE.md \
  config.json \
  settings.json \
  settings.local.json \
  setting.local.json \
  .credentials.json \
  commands \
  output-styles \
  plugins \
  skills; do
  source_path="/mnt/host-configs/claude/$claude_path"
  target_path="$USER_HOME/.claude/$claude_path"
  target_dir="$(dirname "$target_path")"

  if [ -e "$source_path" ]; then
    mkdir -p "$target_dir"
    if [ -L "$target_path" ] || [ ! -e "$target_path" ]; then
      rm -f "$target_path"
      ln -s "$source_path" "$target_path"
    else
      echo "skip existing Claude Code config: $target_path"
    fi
  fi
done

echo "host Maven / Codex / Claude Code config bootstrap completed"
