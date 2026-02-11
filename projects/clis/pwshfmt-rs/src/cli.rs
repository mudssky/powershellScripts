use std::path::PathBuf;

use clap::{Parser, Subcommand};
use serde::Serialize;

use crate::summary::RunMode;

#[derive(Debug, Clone, Parser)]
#[command(
    name = "pwshfmt-rs",
    version,
    about = "PowerShell casing correction CLI (Rust)",
    arg_required_else_help = true
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,

    #[arg(
        long,
        global = true,
        value_name = "FILE",
        help = "配置文件路径（默认自动读取 ./pwshfmt-rs.toml）"
    )]
    pub config: Option<PathBuf>,

    #[arg(
        long,
        global = true,
        num_args = 0..=1,
        default_missing_value = "true",
        value_name = "BOOL",
        help = "是否启用 Git 改动文件模式"
    )]
    pub git_changed: Option<bool>,

    #[arg(
        long = "path",
        global = true,
        value_name = "PATH_OR_GLOB",
        action = clap::ArgAction::Append,
        help = "处理路径或 glob，可重复传入"
    )]
    pub paths: Vec<String>,

    #[arg(
        long,
        global = true,
        num_args = 0..=1,
        default_missing_value = "true",
        value_name = "BOOL",
        help = "目录路径是否递归扫描"
    )]
    pub recurse: Option<bool>,

    #[arg(
        long,
        global = true,
        num_args = 0..=1,
        default_missing_value = "true",
        value_name = "BOOL",
        help = "不安全语法是否回退严格链路"
    )]
    pub strict_fallback: Option<bool>,

    #[arg(long, global = true, value_name = "FILE", help = "严格回退脚本路径")]
    pub fallback_script: Option<PathBuf>,
}

#[derive(Debug, Clone, Subcommand)]
pub enum Commands {
    Check,
    Write,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct CliOverrides {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub git_changed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub paths: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recurse: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strict_fallback: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_script: Option<PathBuf>,
}

impl Cli {
    pub fn run_mode(&self) -> RunMode {
        match self.command {
            Commands::Check => RunMode::Check,
            Commands::Write => RunMode::Write,
        }
    }

    pub fn overrides(&self) -> CliOverrides {
        CliOverrides {
            git_changed: self.git_changed,
            paths: (!self.paths.is_empty()).then_some(self.paths.clone()),
            recurse: self.recurse,
            strict_fallback: self.strict_fallback,
            fallback_script: self.fallback_script.clone(),
        }
    }
}
