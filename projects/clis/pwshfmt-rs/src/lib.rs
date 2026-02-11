pub mod cli;
pub mod config;
pub mod discovery;
pub mod error;
pub mod formatter;
pub mod processor;
pub mod summary;

use std::path::Path;

use clap::Parser;

use crate::cli::Cli;
use crate::error::{AppError, Result};
use crate::processor::{FallbackRunner, PwshFallbackRunner, resolve_fallback_script_path};
use crate::summary::Summary;

pub fn run() -> Result<i32> {
    let cli = Cli::parse();
    run_with_cli(cli)
}

pub fn run_with_cli(cli: Cli) -> Result<i32> {
    let cwd = std::env::current_dir().map_err(|source| AppError::io("读取当前目录", ".", source))?;
    let mode = cli.run_mode();
    let config = config::load(&cli, &cwd)?;

    let fallback_runner = PwshFallbackRunner::new(resolve_fallback_script_path(&cwd, &config), cwd.clone());
    let summary = processor::run(mode, &config, &cwd, &fallback_runner)?;

    Ok(summary.exit_code(mode))
}

pub fn run_with_runner(cli: &Cli, cwd: &Path, fallback_runner: &dyn FallbackRunner) -> Result<Summary> {
    let mode = cli.run_mode();
    let config = config::load(cli, cwd)?;
    processor::run(mode, &config, cwd, fallback_runner)
}
