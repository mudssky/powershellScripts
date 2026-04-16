# shellcheck shell=bash

if [[ -n "${SSM_CMD_INIT_LOADED:-}" ]]; then
  return 0
fi
SSM_CMD_INIT_LOADED=1

# 按“内嵌模板优先、源码模板回退”写出模板文件，兼容单文件分发。
ssm_write_template_file() {
  local template_name="$1"
  local destination="$2"

  if declare -F ssm_write_embedded_template >/dev/null 2>&1; then
    if ssm_write_embedded_template "${template_name}" "${destination}"; then
      return 0
    fi
  fi

  local template_root="${SSM_MANAGER_HOME}/templates"
  cp "${template_root}/${template_name}" "${destination}"
}

# 生成项目目录下的 deploy/systemd 骨架，包含 example 与实际可改文件。
ssm_cmd_init() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  local config_root
  config_root="$(ssm_config_root "${project_dir}")"

  mkdir -p "${config_root}/services" "${config_root}/timers"

  ssm_write_template_file "README.md" "${config_root}/README.md"

  ssm_write_template_file "project.conf.example" "${config_root}/project.conf.example"
  ssm_write_template_file "project.env.example" "${config_root}/project.env.example"
  ssm_write_template_file "project.conf.example" "${config_root}/project.conf"
  ssm_write_template_file "project.env.example" "${config_root}/project.env"

  ssm_write_template_file "service.conf.example" "${config_root}/services/api.conf.example"
  ssm_write_template_file "service.env.example" "${config_root}/services/api.env.example"
  ssm_write_template_file "service.conf.example" "${config_root}/services/api.conf"
  ssm_write_template_file "service.env.example" "${config_root}/services/api.env"

  ssm_write_template_file "timer-service.conf.example" "${config_root}/timers/restart-api.conf.example"
  ssm_write_template_file "timer-service.conf.example" "${config_root}/timers/restart-api.conf"
  ssm_write_template_file "timer-task.conf.example" "${config_root}/timers/cleanup.conf.example"
  ssm_write_template_file "timer-task.conf.example" "${config_root}/timers/cleanup.conf"
}
