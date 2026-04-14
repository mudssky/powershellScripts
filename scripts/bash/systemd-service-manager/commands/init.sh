# shellcheck shell=bash

if [[ -n "${SSM_CMD_INIT_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_INIT_LOADED=1

# 生成项目目录下的 deploy/systemd 骨架，包含 example 与实际可改文件。
ssm_cmd_init() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  local config_root
  config_root="$(ssm_config_root "${project_dir}")"
  local template_root="${SSM_MANAGER_HOME}/templates"

  mkdir -p "${config_root}/services" "${config_root}/timers"

  cp "${template_root}/README.md" "${config_root}/README.md"

  cp "${template_root}/project.conf.example" "${config_root}/project.conf.example"
  cp "${template_root}/project.env.example" "${config_root}/project.env.example"
  cp "${template_root}/project.conf.example" "${config_root}/project.conf"
  cp "${template_root}/project.env.example" "${config_root}/project.env"

  cp "${template_root}/service.conf.example" "${config_root}/services/api.conf.example"
  cp "${template_root}/service.env.example" "${config_root}/services/api.env.example"
  cp "${template_root}/service.conf.example" "${config_root}/services/api.conf"
  cp "${template_root}/service.env.example" "${config_root}/services/api.env"

  cp "${template_root}/timer-service.conf.example" "${config_root}/timers/restart-api.conf.example"
  cp "${template_root}/timer-service.conf.example" "${config_root}/timers/restart-api.conf"
  cp "${template_root}/timer-task.conf.example" "${config_root}/timers/cleanup.conf.example"
  cp "${template_root}/timer-task.conf.example" "${config_root}/timers/cleanup.conf"
}
