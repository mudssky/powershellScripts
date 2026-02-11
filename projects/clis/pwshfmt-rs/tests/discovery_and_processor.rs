mod common;

use std::fs;
use std::path::{Path, PathBuf};

use pwshfmt_rs::{
    config::Config,
    discovery,
    error::Result,
    processor::{self, FallbackRunner},
    summary::RunMode,
};

#[derive(Debug)]
struct NoopFallback;

impl FallbackRunner for NoopFallback {
    fn run_strict(&self, _path: &Path) -> Result<()> {
        Ok(())
    }
}

#[derive(Debug)]
struct RewriteFallback;

impl FallbackRunner for RewriteFallback {
    fn run_strict(&self, path: &Path) -> Result<()> {
        let content = fs::read_to_string(path).expect("read fallback input");
        let replaced = content
            .replace("invoke-expression", "Invoke-Expression")
            .replace("invoke-expression", "Invoke-Expression");
        fs::write(path, replaced).expect("write fallback output");
        Ok(())
    }
}

fn config_with_path(path: &str) -> Config {
    Config {
        git_changed: false,
        paths: vec![path.to_string()],
        recurse: false,
        strict_fallback: false,
        fallback_script: PathBuf::from("scripts/pwsh/devops/Format-PowerShellCode.ps1"),
    }
}

#[test]
fn discovers_files_by_glob_pattern() {
    let workspace = common::create_workspace();
    common::write_file(workspace.path(), "scripts/a.ps1", "Get-ChildItem\n");
    common::write_file(workspace.path(), "scripts/nested/b.psm1", "Get-ChildItem\n");
    common::write_file(workspace.path(), "scripts/c.txt", "ignore\n");

    let mut config = config_with_path("scripts/**/*.ps*");
    config.recurse = true;

    let files = discovery::discover_files(&config, workspace.path()).expect("discover by glob");
    let files_as_string: Vec<String> = files
        .iter()
        .map(|path| {
            path.strip_prefix(workspace.path())
                .unwrap_or(path)
                .to_string_lossy()
                .replace('\\', "/")
        })
        .collect();

    assert_eq!(files.len(), 2);
    assert!(files_as_string.iter().any(|value| value.ends_with("scripts/a.ps1")));
    assert!(
        files_as_string
            .iter()
            .any(|value| value.ends_with("scripts/nested/b.psm1"))
    );
}

#[test]
fn discovers_git_changed_files() {
    let workspace = common::create_workspace();
    common::init_git_repo(workspace.path());

    common::write_file(workspace.path(), "tracked.ps1", "Get-ChildItem\n");
    common::git_commit_all(workspace.path(), "init");

    common::write_file(workspace.path(), "tracked.ps1", "get-childitem -path .\n");

    let config = Config {
        git_changed: true,
        paths: Vec::new(),
        recurse: false,
        strict_fallback: false,
        fallback_script: PathBuf::from("scripts/pwsh/devops/Format-PowerShellCode.ps1"),
    };

    let files = discovery::discover_files(&config, workspace.path()).expect("discover git changed");
    assert_eq!(files.len(), 1);
    assert!(
        files[0]
            .to_string_lossy()
            .replace('\\', "/")
            .ends_with("tracked.ps1")
    );
}

#[test]
fn processor_supports_check_write_and_noop() {
    let workspace = common::create_workspace();
    let file = common::write_file(workspace.path(), "demo.ps1", "get-childitem -path .\n");

    let config = config_with_path("demo.ps1");

    let check_summary =
        processor::run(RunMode::Check, &config, workspace.path(), &NoopFallback).expect("check run");
    assert_eq!(check_summary.needs_fix, 1);
    assert_eq!(check_summary.exit_code(RunMode::Check), 2);

    let write_summary =
        processor::run(RunMode::Write, &config, workspace.path(), &NoopFallback).expect("write run");
    assert_eq!(write_summary.updated, 1);
    assert_eq!(fs::read_to_string(&file).expect("read output"), "Get-ChildItem -Path .\n");

    let noop_summary =
        processor::run(RunMode::Write, &config, workspace.path(), &NoopFallback).expect("noop run");
    assert_eq!(noop_summary.unchanged, 1);
}

#[test]
fn processor_uses_strict_fallback_on_unsafe_tokens() {
    let workspace = common::create_workspace();
    let file = common::write_file(workspace.path(), "unsafe.ps1", "invoke-expression \"Get-ChildItem\"\n");

    let mut config = config_with_path("unsafe.ps1");
    config.strict_fallback = true;

    let check_summary =
        processor::run(RunMode::Check, &config, workspace.path(), &RewriteFallback).expect("check run");
    assert_eq!(check_summary.needs_fix, 1);
    assert_eq!(check_summary.fallback_invoked, 1);
    assert_eq!(check_summary.fallback_changed, 1);

    let write_summary =
        processor::run(RunMode::Write, &config, workspace.path(), &RewriteFallback).expect("write run");
    assert_eq!(write_summary.updated, 1);
    assert_eq!(write_summary.fallback_invoked, 1);
    assert_eq!(write_summary.fallback_changed, 1);

    let content = fs::read_to_string(file).expect("read file");
    assert!(content.contains("Invoke-Expression"));
}
