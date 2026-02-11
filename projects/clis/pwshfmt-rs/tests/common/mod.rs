#![allow(dead_code)]
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use tempfile::TempDir;

pub fn create_workspace() -> TempDir {
    tempfile::tempdir().expect("create temp workspace")
}

pub fn write_file(root: &Path, relative: &str, content: &str) -> PathBuf {
    let path = root.join(relative);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent dirs");
    }
    fs::write(&path, content).expect("write file");
    path
}

pub fn init_git_repo(root: &Path) {
    run_git(root, ["init"]);
    run_git(root, ["config", "user.email", "ci@example.com"]);
    run_git(root, ["config", "user.name", "ci"]);
}

pub fn git_commit_all(root: &Path, message: &str) {
    run_git(root, ["add", "."]);
    run_git(root, ["commit", "-m", message]);
}

fn run_git<const N: usize>(root: &Path, args: [&str; N]) {
    let output = Command::new("git")
        .current_dir(root)
        .args(args)
        .output()
        .expect("run git");

    if output.status.success() {
        return;
    }

    panic!(
        "git {:?} failed: {}",
        args,
        String::from_utf8_lossy(&output.stderr)
    );
}
