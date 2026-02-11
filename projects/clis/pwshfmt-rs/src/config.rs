use std::path::{Path, PathBuf};

use figment::{
    Figment,
    providers::{Env, Format, Serialized, Toml},
};
use serde::{Deserialize, Serialize};

use crate::{
    cli::Cli,
    error::{AppError, Result},
};

pub const DEFAULT_CONFIG_FILE: &str = "pwshfmt-rs.toml";
pub const ENV_PREFIX: &str = "PWSHFMT_RS_";
pub const DEFAULT_FALLBACK_SCRIPT: &str = "scripts/pwsh/devops/Format-PowerShellCode.ps1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct Config {
    pub git_changed: bool,
    pub paths: Vec<String>,
    pub recurse: bool,
    pub strict_fallback: bool,
    pub fallback_script: PathBuf,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            git_changed: false,
            paths: Vec::new(),
            recurse: false,
            strict_fallback: false,
            fallback_script: PathBuf::from(DEFAULT_FALLBACK_SCRIPT),
        }
    }
}

pub fn load(cli: &Cli, cwd: &Path) -> Result<Config> {
    let config_path = resolve_config_path(cli, cwd);
    let mut figment = Figment::from(Serialized::defaults(Config::default()));

    if cli.config.is_some() {
        if !config_path.is_file() {
            return Err(AppError::ConfigFileMissing { path: config_path });
        }
        figment = figment.merge(Toml::file(&config_path));
    } else if config_path.is_file() {
        figment = figment.merge(Toml::file(&config_path));
    }

    figment = figment.merge(Env::prefixed(ENV_PREFIX).split("__"));
    figment = figment.merge(Serialized::defaults(cli.overrides()));

    let mut config = figment
        .extract::<Config>()
        .map_err(|source| AppError::ConfigLoad { source })?;

    normalize_config(&mut config);
    validate_config(&config, cwd)?;

    Ok(config)
}

fn resolve_config_path(cli: &Cli, cwd: &Path) -> PathBuf {
    let raw = cli
        .config
        .clone()
        .unwrap_or_else(|| PathBuf::from(DEFAULT_CONFIG_FILE));
    if raw.is_absolute() {
        raw
    } else {
        cwd.join(raw)
    }
}

fn normalize_config(config: &mut Config) {
    config.paths = config
        .paths
        .iter()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .collect();
}

fn validate_config(config: &Config, cwd: &Path) -> Result<()> {
    if !config.git_changed && config.paths.is_empty() {
        return Err(AppError::invalid_arguments(
            "必须至少启用一种目标选择方式：--git-changed 或 --path",
        ));
    }

    if config.strict_fallback {
        let script_path = if config.fallback_script.is_absolute() {
            config.fallback_script.clone()
        } else {
            cwd.join(&config.fallback_script)
        };

        if !script_path.is_file() {
            return Err(AppError::invalid_arguments(format!(
                "strict_fallback 已启用，但脚本不存在: {}",
                script_path.display()
            )));
        }
    }

    Ok(())
}
