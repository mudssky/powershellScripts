use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::config::Config;
use crate::discovery::discover_files;
use crate::error::{AppError, Result};
use crate::formatter::format_content;
use crate::summary::{FileReport, FileStatus, RunMode, Summary};

static TEMP_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

pub trait FallbackRunner: Send + Sync {
    fn run_strict(&self, path: &Path) -> Result<()>;
}

#[derive(Debug, Clone)]
pub struct PwshFallbackRunner {
    script_path: PathBuf,
    working_dir: PathBuf,
}

impl PwshFallbackRunner {
    pub fn new(script_path: PathBuf, working_dir: PathBuf) -> Self {
        Self {
            script_path,
            working_dir,
        }
    }
}

impl FallbackRunner for PwshFallbackRunner {
    fn run_strict(&self, path: &Path) -> Result<()> {
        let output = Command::new("pwsh")
            .current_dir(&self.working_dir)
            .args(["-NoProfile", "-File"])
            .arg(&self.script_path)
            .arg(path)
            .arg("-Strict")
            .output()
            .map_err(|source| AppError::FallbackFailed {
                path: path.to_path_buf(),
                message: format!("调用 pwsh 失败: {source}"),
            })?;

        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();

        let message = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("退出码异常: {:?}", output.status.code())
        };

        Err(AppError::FallbackFailed {
            path: path.to_path_buf(),
            message,
        })
    }
}

pub fn resolve_fallback_script_path(cwd: &Path, config: &Config) -> PathBuf {
    if config.fallback_script.is_absolute() {
        config.fallback_script.clone()
    } else {
        cwd.join(&config.fallback_script)
    }
}

pub fn run(
    mode: RunMode,
    config: &Config,
    cwd: &Path,
    fallback_runner: &dyn FallbackRunner,
) -> Result<Summary> {
    let files = discover_files(config, cwd)?;
    if files.is_empty() {
        println!("INFO 未发现需要处理的 PowerShell 文件，快速退出");
        return Ok(Summary::default());
    }

    println!(
        "INFO mode={mode:?}, files={}, strict_fallback={}",
        files.len(),
        config.strict_fallback
    );

    let mut summary = Summary::default();

    for path in files {
        let report = process_file(&path, mode, config, fallback_runner);
        print_file_report(&report);
        summary.track(&report);
    }

    print_summary(&summary);
    Ok(summary)
}

fn process_file(
    path: &Path,
    mode: RunMode,
    config: &Config,
    fallback_runner: &dyn FallbackRunner,
) -> FileReport {
    let original = match fs::read_to_string(path) {
        Ok(value) => value,
        Err(error) => {
            return FileReport::failed(path.to_path_buf(), format!("读取文件失败: {error}"));
        }
    };

    let correction = format_content(&original);

    if correction.unsafe_detected {
        if !config.strict_fallback {
            return FileReport::failed(
                path.to_path_buf(),
                "检测到不安全语法，且 strict_fallback=false",
            );
        }

        return match mode {
            RunMode::Check => match run_fallback_check(path, &original, fallback_runner) {
                Ok(changed) if changed => {
                    FileReport::needs_fix(path.to_path_buf(), 0, 0).with_fallback(true)
                }
                Ok(_) => FileReport::unchanged(path.to_path_buf(), 0, 0).with_fallback(false),
                Err(error) => {
                    FileReport::failed(path.to_path_buf(), format!("严格回退失败: {error}"))
                }
            },
            RunMode::Write => match run_fallback_write(path, &original, fallback_runner) {
                Ok(changed) if changed => {
                    FileReport::updated(path.to_path_buf(), 0, 0).with_fallback(true)
                }
                Ok(_) => FileReport::unchanged(path.to_path_buf(), 0, 0).with_fallback(false),
                Err(error) => {
                    FileReport::failed(path.to_path_buf(), format!("严格回退失败: {error}"))
                }
            },
        };
    }

    if correction.formatted == original {
        return FileReport::unchanged(
            path.to_path_buf(),
            correction.command_fixes,
            correction.parameter_fixes,
        );
    }

    match mode {
        RunMode::Check => FileReport::needs_fix(
            path.to_path_buf(),
            correction.command_fixes,
            correction.parameter_fixes,
        ),
        RunMode::Write => match fs::write(path, correction.formatted.as_bytes()) {
            Ok(()) => FileReport::updated(
                path.to_path_buf(),
                correction.command_fixes,
                correction.parameter_fixes,
            ),
            Err(error) => FileReport::failed(path.to_path_buf(), format!("写回失败: {error}")),
        },
    }
}

fn run_fallback_check(path: &Path, original: &str, fallback_runner: &dyn FallbackRunner) -> Result<bool> {
    let temp_file = build_temp_path(path);
    fs::write(&temp_file, original.as_bytes())
        .map_err(|source| AppError::io("写入临时文件", &temp_file, source))?;

    let run_result = fallback_runner.run_strict(&temp_file);
    let formatted_result = fs::read_to_string(&temp_file)
        .map_err(|source| AppError::io("读取临时文件", &temp_file, source));

    if let Err(error) = fs::remove_file(&temp_file) {
        eprintln!("WARN 删除临时文件失败: {}: {error}", temp_file.display());
    }

    run_result?;
    let formatted = formatted_result?;

    Ok(formatted != original)
}

fn run_fallback_write(path: &Path, original: &str, fallback_runner: &dyn FallbackRunner) -> Result<bool> {
    fallback_runner.run_strict(path)?;
    let formatted =
        fs::read_to_string(path).map_err(|source| AppError::io("读取回退结果", path, source))?;
    Ok(formatted != original)
}

fn build_temp_path(source_path: &Path) -> PathBuf {
    let extension = source_path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("ps1");

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let counter = TEMP_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);

    env::temp_dir().join(format!("pwshfmt-rs-{timestamp}-{counter}.{extension}"))
}

fn print_file_report(report: &FileReport) {
    let status = match report.status {
        FileStatus::Unchanged => "UNCHANGED",
        FileStatus::NeedsFix => "NEEDS_FIX",
        FileStatus::Updated => "UPDATED",
        FileStatus::Failed => "FAILED",
    };

    if let Some(detail) = &report.detail {
        eprintln!("{status} {} ({detail})", report.path.display());
    } else {
        println!(
            "{status} {} (command_fixes={}, parameter_fixes={}, fallback={})",
            report.path.display(),
            report.command_fixes,
            report.parameter_fixes,
            report.fallback_invoked
        );
    }
}

fn print_summary(summary: &Summary) {
    println!(
        "SUMMARY total={} unchanged={} needs_fix={} updated={} failed={} fallback_invoked={} fallback_changed={} command_fixes={} parameter_fixes={}",
        summary.total,
        summary.unchanged,
        summary.needs_fix,
        summary.updated,
        summary.failed,
        summary.fallback_invoked,
        summary.fallback_changed,
        summary.command_fixes,
        summary.parameter_fixes
    );
}
