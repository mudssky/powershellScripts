use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

use globset::GlobBuilder;
use walkdir::WalkDir;

use crate::{
    config::Config,
    error::{AppError, Result},
};

const SUPPORTED_EXTENSIONS: [&str; 3] = ["ps1", "psm1", "psd1"];

pub fn discover_files(config: &Config, cwd: &Path) -> Result<Vec<PathBuf>> {
    let mut deduped = BTreeSet::new();

    if config.git_changed {
        collect_git_changed_files(cwd, &mut deduped)?;
    }

    for raw in &config.paths {
        collect_files_from_path_or_pattern(cwd, raw, config.recurse, &mut deduped)?;
    }

    Ok(deduped.into_iter().collect())
}

fn collect_git_changed_files(cwd: &Path, deduped: &mut BTreeSet<PathBuf>) -> Result<()> {
    let git_root = git_repo_root(cwd)?;

    for cached in [false, true] {
        let mut command = Command::new("git");
        command
            .current_dir(&git_root)
            .args(["diff", "--name-only", "--diff-filter=ACMRTUXB"]);

        if cached {
            command.arg("--cached");
        }

        command.arg("--");
        command.args(["*.ps1", "*.psm1", "*.psd1"]);

        let output = command.output().map_err(|source| AppError::GitCommandFailed {
            message: format!("执行 git diff 失败: {source}"),
        })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            return Err(AppError::GitCommandFailed {
                message: if stderr.is_empty() {
                    format!("git diff 退出码异常: {:?}", output.status.code())
                } else {
                    stderr
                },
            });
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines().map(str::trim).filter(|line| !line.is_empty()) {
            let candidate = git_root.join(line);
            if candidate.is_file() && is_supported_pwsh_file(&candidate) {
                deduped.insert(normalize_existing_path(&candidate));
            }
        }
    }

    Ok(())
}

fn git_repo_root(cwd: &Path) -> Result<PathBuf> {
    let output = Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .map_err(|source| AppError::GitCommandFailed {
            message: format!("执行 git rev-parse 失败: {source}"),
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(AppError::GitCommandFailed {
            message: if stderr.is_empty() {
                "当前目录不在 Git 仓库内".to_string()
            } else {
                format!("当前目录不在 Git 仓库内: {stderr}")
            },
        });
    }

    let root = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if root.is_empty() {
        return Err(AppError::GitCommandFailed {
            message: "Git 仓库根目录为空".to_string(),
        });
    }

    Ok(PathBuf::from(root))
}

fn collect_files_from_path_or_pattern(
    cwd: &Path,
    raw: &str,
    recurse: bool,
    deduped: &mut BTreeSet<PathBuf>,
) -> Result<()> {
    let resolved_path = resolve_from_cwd(cwd, Path::new(raw));

    if resolved_path.exists() {
        return collect_files_from_real_path(&resolved_path, recurse, deduped);
    }

    collect_files_from_pattern(cwd, raw, recurse, deduped)
}

fn collect_files_from_real_path(
    path: &Path,
    recurse: bool,
    deduped: &mut BTreeSet<PathBuf>,
) -> Result<()> {
    if path.is_file() {
        if is_supported_pwsh_file(path) {
            deduped.insert(normalize_existing_path(path));
        }
        return Ok(());
    }

    if !path.is_dir() {
        return Ok(());
    }

    let mut walker = WalkDir::new(path).follow_links(false);
    if !recurse {
        walker = walker.max_depth(1);
    }

    for entry in walker {
        let entry = entry.map_err(|error| {
            let error_path = error.path().unwrap_or(path).to_path_buf();
            AppError::io("遍历目录", error_path, std::io::Error::other(error.to_string()))
        })?;

        if !entry.file_type().is_file() {
            continue;
        }

        let candidate = entry.path();
        if is_supported_pwsh_file(candidate) {
            deduped.insert(normalize_existing_path(candidate));
        }
    }

    Ok(())
}

fn collect_files_from_pattern(
    cwd: &Path,
    pattern: &str,
    recurse: bool,
    deduped: &mut BTreeSet<PathBuf>,
) -> Result<()> {
    let normalized_pattern = pattern.replace('\\', "/");
    let glob = GlobBuilder::new(&normalized_pattern)
        .literal_separator(false)
        .build()
        .map_err(|source| AppError::InvalidGlob {
            pattern: pattern.to_string(),
            source,
        })?;
    let matcher = glob.compile_matcher();

    let base_dir = pattern_base_dir(pattern);
    let base_abs = resolve_from_cwd(cwd, &base_dir);
    if !base_abs.exists() {
        return Ok(());
    }

    let mut walker = WalkDir::new(&base_abs).follow_links(false);
    if !recurse {
        walker = walker.max_depth(1);
    }

    for entry in walker {
        let entry = entry.map_err(|error| {
            let error_path = error.path().unwrap_or(&base_abs).to_path_buf();
            AppError::io("遍历模式目录", error_path, std::io::Error::other(error.to_string()))
        })?;

        if !entry.file_type().is_file() {
            continue;
        }

        let candidate = entry.path();
        if !is_supported_pwsh_file(candidate) {
            continue;
        }

        let relative_to_cwd = candidate.strip_prefix(cwd).unwrap_or(candidate);
        let relative_to_base = candidate.strip_prefix(&base_abs).unwrap_or(candidate);

        let candidate_norm = normalize_for_glob(candidate);
        let rel_cwd_norm = normalize_for_glob(relative_to_cwd);
        let rel_base_norm = normalize_for_glob(relative_to_base);

        let matched = matcher.is_match(Path::new(&candidate_norm))
            || matcher.is_match(Path::new(&rel_cwd_norm))
            || matcher.is_match(Path::new(&rel_base_norm));

        if matched {
            deduped.insert(normalize_existing_path(candidate));
        }
    }

    Ok(())
}

fn pattern_base_dir(pattern: &str) -> PathBuf {
    let wildcard_index = pattern
        .char_indices()
        .find(|(_, character)| matches!(character, '*' | '?' | '['))
        .map(|(index, _)| index)
        .unwrap_or(pattern.len());

    let prefix = &pattern[..wildcard_index];
    let last_separator = prefix.rfind(|character| character == '/' || character == '\\');

    match last_separator {
        Some(index) if index > 0 => PathBuf::from(&pattern[..index]),
        Some(_) => PathBuf::from(std::path::MAIN_SEPARATOR.to_string()),
        None => PathBuf::from("."),
    }
}

fn resolve_from_cwd(cwd: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        cwd.join(path)
    }
}

fn normalize_for_glob(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn normalize_existing_path(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

fn is_supported_pwsh_file(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|value| value.to_str()) else {
        return false;
    };

    SUPPORTED_EXTENSIONS
        .iter()
        .any(|candidate| ext.eq_ignore_ascii_case(candidate))
}
